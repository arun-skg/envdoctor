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
                    message="used in source code but not defined in any environment file",
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
