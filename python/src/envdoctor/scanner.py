"""Core environment-variable consistency scanner (native Python port).

Local-first: reads ``.env`` files and scans Python source for environment
access, then reconciles the two. No network, no telemetry, values never printed.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

# Source usage patterns. Each captures the variable name in group 1.
_USAGE_PATTERNS = [
    re.compile(r"\bos\.environ\.get\(\s*[\"']([A-Za-z_]\w*)[\"']"),
    re.compile(r"\bos\.getenv\(\s*[\"']([A-Za-z_]\w*)[\"']"),
    re.compile(r"\bos\.environ\[\s*[\"']([A-Za-z_]\w*)[\"']\s*\]"),
    re.compile(r"\benviron\.get\(\s*[\"']([A-Za-z_]\w*)[\"']"),
    re.compile(r"\benviron\[\s*[\"']([A-Za-z_]\w*)[\"']\s*\]"),
]

# Triple-quoted docstrings are stripped so example code inside them is ignored.
_DOCSTRING = re.compile(r"\"\"\".*?\"\"\"|'''.*?'''", re.DOTALL)
_LINE_COMMENT = re.compile(r"#[^\n]*")

# --- Infra source scanning (Docker Compose / GitHub Actions / Kubernetes) ---
# Dependency-free: regex/line scanning only, interpolation refs only.
_COMPOSE_BASENAME = re.compile(r"^(docker-)?compose([.-].*)?\.ya?ml$", re.IGNORECASE)
_INTERP_BRACE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)")
_INTERP_BARE = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")
_ACTIONS_REF = re.compile(r"\b(?:secrets|vars|env)\.([A-Za-z_][A-Za-z0-9_]*)")
_K8S_APIVERSION = re.compile(r"(?m)^apiVersion:")
_K8S_KIND = re.compile(r"(?m)^kind:")
_INFRA_SKIP_DIRS = {".git", "vendor", "node_modules", "target"}

_ENV_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=(.*)$")

# Public/client-exposed environment prefixes (case-sensitive, exact).
_PUBLIC_PREFIXES = (
    "NEXT_PUBLIC_",
    "VITE_",
    "REACT_APP_",
    "EXPO_PUBLIC_",
    "GATSBY_",
    "NUXT_PUBLIC_",
    "VUE_APP_",
    "PUBLIC_",
)

# Secret-looking name pattern (case-insensitive).
_SECRET_NAME = re.compile(
    r"SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|API_?KEY|ACCESS_?KEY|AUTH",
    re.IGNORECASE,
)

# Weak/placeholder secret value pattern (case-insensitive, whole-value).
_WEAK_SECRET_VALUE = re.compile(
    r"^(changeme|change_me|placeholder|x{3,}|todo|secret|password|passwd|test|"
    r"example|sample|dummy|your[_-].*|<.*>|\$\{.*\})$",
    re.IGNORECASE,
)

_INT_RE = re.compile(r"^-?\d+$")
_FLOAT_RE = re.compile(r"^-?\d+\.\d+$")
_URL_RE = re.compile(r"^https?://", re.IGNORECASE)


@dataclass
class Origin:
    file: Path
    line: int


@dataclass
class Finding:
    rule: str
    severity: str  # "error" | "warning"
    name: str
    message: str
    origin: Origin | None = None


@dataclass
class ScanResult:
    findings: list[Finding] = field(default_factory=list)

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.severity == "error"]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self.findings if f.severity == "warning"]


def _strip_noise(code: str) -> str:
    """Blank docstrings and comments while preserving line structure."""

    def blank(match: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", match.group(0))

    code = _DOCSTRING.sub(blank, code)
    code = _LINE_COMMENT.sub(blank, code)
    return code


def parse_value(raw_rhs: str) -> str:
    """Trim the right-hand side and strip one matching pair of surrounding quotes."""
    v = raw_rhs.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        v = v[1:-1]
    return v


def env_label(filename: str) -> str:
    """Derive an environment label from a dotenv filename."""
    if filename == ".env":
        return "default"
    # filename starts with ".env." here (discover filters accordingly).
    rest = filename[len(".env."):]
    if rest == "local":
        return "local"
    if rest.endswith(".local"):
        rest = rest[: -len(".local")]
    return rest


def infer_type(value: str) -> str:
    """Infer a coarse type from a value string."""
    if value == "":
        return "empty"
    if _INT_RE.match(value):
        return "integer"
    if _FLOAT_RE.match(value):
        return "float"
    if value.lower() in ("true", "false"):
        return "boolean"
    if _URL_RE.match(value):
        return "url"
    if value[0] in ("{", "["):
        try:
            json.loads(value)
            return "json"
        except ValueError:
            pass
    return "string"


def compat_group(inferred: str) -> str:
    """Map an inferred type to its compatibility group."""
    if inferred in ("integer", "float"):
        return "numeric"
    return inferred


def levenshtein(a: str, b: str) -> int:
    """Classic dynamic-programming Levenshtein edit distance."""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        cur = [i]
        for j, cb in enumerate(b, start=1):
            cost = 0 if ca == cb else 1
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost))
        prev = cur
    return prev[-1]


@dataclass
class _Def:
    origin: Origin
    values: dict[str, str] = field(default_factory=dict)  # label -> value


def parse_env_file(path: Path) -> dict[str, list[tuple[Origin, str]]]:
    """Return ``{NAME: [(Origin, value), ...]}`` for every definition in a file."""
    defined: dict[str, list[tuple[Origin, str]]] = {}
    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = _ENV_LINE.match(raw)
        if match:
            value = parse_value(match.group(2))
            defined.setdefault(match.group(1), []).append((Origin(path, lineno), value))
    return defined


def scan_source_file(path: Path) -> dict[str, Origin]:
    """Return ``{NAME: first Origin}`` for env usages in a Python source file."""
    text = _strip_noise(path.read_text())
    used: dict[str, Origin] = {}
    for pattern in _USAGE_PATTERNS:
        for match in pattern.finditer(text):
            name = match.group(1)
            line = text.count("\n", 0, match.start()) + 1
            used.setdefault(name, Origin(path, line))
    return used


def _has_workflows_segment(path: Path) -> bool:
    """True if the path contains a ``.github/workflows/`` directory segment."""
    parts = path.parts
    for i in range(len(parts) - 1):
        if parts[i] == ".github" and parts[i + 1] == "workflows":
            return True
    return False


def discover_infra_files(root: Path) -> list[tuple[Path, str]]:
    """Return ``[(path, kind), ...]`` for Compose/Actions/Kubernetes YAML files.

    ``kind`` is one of ``"compose"``, ``"actions"``, ``"k8s"``. Classification is
    purely by filename/path/content, with no YAML parsing.
    """
    out: list[tuple[Path, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if any(part in _INFRA_SKIP_DIRS for part in path.parts):
            continue
        base = path.name
        low = base.lower()
        is_yaml = low.endswith(".yml") or low.endswith(".yaml")
        if _COMPOSE_BASENAME.match(base):
            out.append((path, "compose"))
            continue
        if is_yaml and _has_workflows_segment(path):
            out.append((path, "actions"))
            continue
        if is_yaml:
            try:
                text = path.read_text()
            except (OSError, UnicodeDecodeError):
                continue
            if _K8S_APIVERSION.search(text) and _K8S_KIND.search(text):
                out.append((path, "k8s"))
    return out


def scan_infra_file(path: Path, kind: str) -> dict[str, Origin]:
    """Return ``{NAME: first Origin}`` for interpolation refs in an infra file.

    Escaped ``$$`` is neutralized first (offset-preserving). Interpolation refs
    apply to all kinds; GitHub Actions additionally matches
    ``secrets.X``/``vars.X``/``env.X`` references.
    """
    text = path.read_text().replace("$$", "  ")
    used: dict[str, Origin] = {}
    patterns = [_INTERP_BRACE, _INTERP_BARE]
    if kind == "actions":
        patterns.append(_ACTIONS_REF)
    for pattern in patterns:
        for match in pattern.finditer(text):
            name = match.group(1)
            line = text.count("\n", 0, match.start()) + 1
            used.setdefault(name, Origin(path, line))
    return used


def discover_env_files(root: Path) -> list[Path]:
    files = sorted(root.glob(".env"))
    files += sorted(p for p in root.glob(".env.*") if not p.name.endswith(".example"))
    return files


def defined_by_label(root: Path) -> dict[str, set[str]]:
    """Map each environment label to the set of variable names defined in it."""
    labels: dict[str, set[str]] = {}
    for env_file in discover_env_files(root):
        names = labels.setdefault(env_label(env_file.name), set())
        for name in parse_env_file(env_file):
            names.add(name)
    return labels


def diff_labels(root: Path, a: str, b: str) -> dict[str, list[str]]:
    """Compare the variable names defined in two environment labels."""
    labels = defined_by_label(root)
    da = labels.get(a, set())
    db = labels.get(b, set())
    return {
        "onlyInA": sorted(da - db),
        "onlyInB": sorted(db - da),
        "common": sorted(da & db),
    }


def sync_labels(root: Path, src: str, dst: str, dry_run: bool = False) -> list[str]:
    """Append keys present in ``src`` but missing from ``dst`` to dst's file.

    Values are never copied — only ``KEY=`` placeholders are written.
    """
    labels = defined_by_label(root)
    missing = sorted(labels.get(src, set()) - labels.get(dst, set()))
    if missing and not dry_run:
        target = root / (".env" if dst == "default" else f".env.{dst}")
        existing = target.read_text() if target.exists() else ""
        prefix = "" if existing == "" or existing.endswith("\n") else "\n"
        with target.open("a") as fh:
            fh.write(prefix + "".join(f"{k}=\n" for k in missing))
    return missing


def collect_names(
    root: Path, extensions: Iterable[str] = ("py",)
) -> tuple[set[str], set[str]]:
    """Return ``(defined, used)`` name sets, computed exactly as :func:`scan` does.

    ``defined`` is every name defined in any ``.env*`` file; ``used`` is every
    name referenced in source or infra (Compose/Actions/Kubernetes) files.
    """
    defined: set[str] = set()
    for env_file in discover_env_files(root):
        for name in parse_env_file(env_file):
            defined.add(name)
    used: set[str] = set()
    for src in discover_source_files(root, extensions):
        used.update(scan_source_file(src))
    for infra_path, kind in discover_infra_files(root):
        used.update(scan_infra_file(infra_path, kind))
    return defined, used


def render_env_example(defined: set[str], used: set[str]) -> str:
    """Render ``.env.example`` content from the union of names. Values omitted."""
    lines = ["# Generated by envdoctor. Fill in values; do not commit secrets."]
    for name in sorted(defined | used):
        lines.append(f"{name}=")
    return "\n".join(lines) + "\n"


def render_environment_md(defined: set[str], used: set[str]) -> str:
    """Render ``ENVIRONMENT.md`` content from the union of names. Values omitted."""
    lines = [
        "# Environment variables",
        "",
        "| Variable | Defined | Used |",
        "| --- | --- | --- |",
    ]
    for name in sorted(defined | used):
        d = "yes" if name in defined else "no"
        u = "yes" if name in used else "no"
        lines.append(f"| {name} | {d} | {u} |")
    return "\n".join(lines) + "\n"


# Generated docs, in output order.
GENERATED_FILES = (".env.example", "ENVIRONMENT.md")

_NUMERIC = re.compile(r"^-?\d+(\.\d+)?$")


def load_schema(root: Path) -> dict:
    """Load ``envdoctor.schema.json`` from the project root, or {} if absent/invalid."""
    path = root / "envdoctor.schema.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _type_ok(value: str, declared: str) -> bool:
    if declared == "string":
        return True
    if declared == "integer":
        return re.fullmatch(r"-?\d+", value) is not None
    if declared == "float":
        return re.fullmatch(r"-?\d+(\.\d+)?", value) is not None
    if declared == "boolean":
        return value.lower() in ("true", "false")
    if declared == "url":
        return re.match(r"https?://", value) is not None
    if declared == "json":
        try:
            json.loads(value)
            return True
        except ValueError:
            return False
    return True


def schema_failure(rule: dict, value: str) -> str | None:
    """Return the first schema-check failure message for ``value``, or None."""
    declared = rule.get("type")
    if isinstance(declared, str) and not _type_ok(value, declared):
        return f"value does not match schema type {declared}"
    enum = rule.get("enum")
    if isinstance(enum, list) and value not in enum:
        return "value is not one of the allowed values"
    pattern = rule.get("regex")
    if isinstance(pattern, str) and re.search(pattern, value) is None:
        return "value does not match the required pattern"
    if _NUMERIC.match(value):
        num = float(value)
        lo = rule.get("min")
        if isinstance(lo, (int, float)) and num < lo:
            return "value is below the minimum"
        hi = rule.get("max")
        if isinstance(hi, (int, float)) and num > hi:
            return "value exceeds the maximum"
    return None


def generate_docs(root: Path, extensions: Iterable[str] = ("py",)) -> dict[str, str]:
    """Return ``{filename: content}`` for the two generated files."""
    defined, used = collect_names(root, extensions)
    return {
        ".env.example": render_env_example(defined, used),
        "ENVIRONMENT.md": render_environment_md(defined, used),
    }


def discover_source_files(root: Path, extensions: Iterable[str] = ("py",)) -> list[Path]:
    exts = {e.lstrip(".").lower() for e in extensions}
    out: list[Path] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if any(part in {".git", "__pycache__", ".venv", "node_modules"} for part in path.parts):
            continue
        if path.suffix.lstrip(".").lower() in exts:
            out.append(path)
    return out


def scan(root: Path, extensions: Iterable[str] = ("py",)) -> ScanResult:
    """Reconcile dotenv definitions against source usage under ``root``."""
    defined: dict[str, _Def] = {}
    project_labels: set[str] = set()
    duplicates: list[Finding] = []

    for env_file in discover_env_files(root):
        label = env_label(env_file.name)
        project_labels.add(label)
        for name, occurrences in parse_env_file(env_file).items():
            first_origin, first_value = occurrences[0]
            if name not in defined:
                defined[name] = _Def(origin=first_origin)
            # First value seen for this label wins.
            if label not in defined[name].values:
                defined[name].values[label] = first_value
            # Duplicate within a single file: 2+ occurrences of the same key.
            if len(occurrences) >= 2:
                lines = ", ".join(str(o.line) for o, _ in occurrences)
                duplicates.append(
                    Finding(
                        rule="duplicates",
                        severity="error",
                        name=name,
                        message=(
                            f"defined {len(occurrences)} times in the same file "
                            f"(lines {lines})"
                        ),
                        origin=first_origin,
                    )
                )

    used: dict[str, Origin] = {}
    for src in discover_source_files(root, extensions):
        for name, origin in scan_source_file(src).items():
            used.setdefault(name, origin)

    # Docker Compose / GitHub Actions / Kubernetes files also reference vars.
    for infra_path, kind in discover_infra_files(root):
        for name, origin in scan_infra_file(infra_path, kind).items():
            used.setdefault(name, origin)

    result = ScanResult()

    # --- Errors, in rule order ---

    # undefined-in-source: used but never defined.
    for name in sorted(used):
        if name not in defined:
            result.findings.append(
                Finding(
                    rule="undefined-in-source",
                    severity="error",
                    name=name,
                    message="referenced but not defined in any environment file",
                    origin=used[name],
                )
            )

    # duplicates: same key defined 2+ times within a single .env file.
    for finding in sorted(duplicates, key=lambda f: f.name):
        result.findings.append(finding)

    # public-prefix: secret-looking var exposed to client bundles.
    for name in sorted(defined):
        if name.startswith(_PUBLIC_PREFIXES) and _SECRET_NAME.search(name):
            result.findings.append(
                Finding(
                    rule="public-prefix",
                    severity="error",
                    name=name,
                    message=(
                        "secret-looking variable is exposed to client bundles "
                        "via a public prefix"
                    ),
                    origin=defined[name].origin,
                )
            )

    # type-mismatch: incompatible inferred types across environments.
    for name in sorted(defined):
        d = defined[name]
        if len(d.values) < 2:
            continue
        groups = set()
        for value in d.values.values():
            t = infer_type(value)
            if t == "empty":
                continue
            groups.add(compat_group(t))
        if len(groups) >= 2:
            result.findings.append(
                Finding(
                    rule="type-mismatch",
                    severity="error",
                    name=name,
                    message="inferred type differs across environments",
                    origin=d.origin,
                )
            )

    # schema-validation: values must satisfy envdoctor.schema.json rules.
    schema = load_schema(root)
    for name in sorted(schema):
        rule = schema[name]
        if not isinstance(rule, dict):
            continue
        d = defined.get(name)
        if d is None:
            if not rule.get("optional"):
                result.findings.append(
                    Finding(
                        rule="schema-validation",
                        severity="error",
                        name=name,
                        message="required by schema but not defined",
                        origin=None,
                    )
                )
            continue
        value = next(iter(d.values.values()), "")
        msg = schema_failure(rule, value)
        if msg:
            result.findings.append(
                Finding(
                    rule="schema-validation",
                    severity="error",
                    name=name,
                    message=msg,
                    origin=d.origin,
                )
            )

    # --- Warnings, in rule order ---

    # unused: defined but never referenced.
    for name in sorted(defined):
        if name not in used:
            result.findings.append(
                Finding(
                    rule="unused",
                    severity="warning",
                    name=name,
                    message="defined but never referenced in source",
                    origin=defined[name].origin,
                )
            )

    # environment-diff: defined in some but not all project env labels.
    if len(project_labels) >= 2:
        for name in sorted(defined):
            present = sorted(defined[name].values)
            absent = sorted(project_labels - set(present))
            if present and absent:
                result.findings.append(
                    Finding(
                        rule="environment-diff",
                        severity="warning",
                        name=name,
                        message=(
                            f"defined in {', '.join(present)} but missing in "
                            f"{', '.join(absent)}"
                        ),
                        origin=defined[name].origin,
                    )
                )

    # weak-secret: secret-looking name with a weak or placeholder value.
    for name in sorted(defined):
        if not _SECRET_NAME.search(name):
            continue
        value = defined[name].values.get(env_label(defined[name].origin.file.name))
        if value is None:
            value = next(iter(defined[name].values.values()), "")
        if value == "" or len(value) < 8 or _WEAK_SECRET_VALUE.match(value):
            result.findings.append(
                Finding(
                    rule="weak-secret",
                    severity="warning",
                    name=name,
                    message="secret-looking variable has a weak or placeholder value",
                    origin=defined[name].origin,
                )
            )

    # typo: used-but-undefined name close to a defined name.
    defined_names = list(defined)
    for u in sorted(used):
        if u in defined:
            continue
        best_d: str | None = None
        best_dist = 0
        for d in sorted(defined_names):
            if d == u:
                continue
            threshold = 1 if min(len(u), len(d)) <= 4 else 2
            dist = levenshtein(u, d)
            if dist <= threshold and (best_d is None or dist < best_dist):
                best_d, best_dist = d, dist
        if best_d is not None:
            result.findings.append(
                Finding(
                    rule="typo",
                    severity="warning",
                    name=u,
                    message=f'"{u}" is not defined; did you mean "{best_d}"?',
                    origin=used[u],
                )
            )

    return result


def finding_to_dict(finding: Finding, root: Path) -> dict:
    """Serialize a finding for JSON output. Values are never included."""
    file = None
    line = None
    if finding.origin is not None:
        try:
            file = str(finding.origin.file.relative_to(root))
        except ValueError:
            file = str(finding.origin.file)
        line = finding.origin.line
    return {
        "rule": finding.rule,
        "severity": finding.severity,
        "name": finding.name,
        "message": finding.message,
        "file": file,
        "line": line,
    }
