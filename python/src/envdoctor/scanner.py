"""Core environment-variable consistency scanner (native Python port).

Local-first: reads ``.env`` files and scans Python source for environment
access, then reconciles the two. No network, no telemetry, values never printed.
"""

from __future__ import annotations

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

_ENV_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_]\w*)\s*=")


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


def parse_env_file(path: Path) -> dict[str, Origin]:
    """Return ``{NAME: Origin}`` for the definitions in a dotenv file."""
    defined: dict[str, Origin] = {}
    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = _ENV_LINE.match(raw)
        if match:
            defined.setdefault(match.group(1), Origin(path, lineno))
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
    defined: dict[str, Origin] = {}
    for env_file in discover_env_files(root):
        defined.update(parse_env_file(env_file))

    used: dict[str, Origin] = {}
    for src in discover_source_files(root, extensions):
        for name, origin in scan_source_file(src).items():
            used.setdefault(name, origin)

    result = ScanResult()

    # missing / undefined-in-source: used but never defined.
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

    # unused: defined but never referenced.
    for name in sorted(defined):
        if name not in used:
            result.findings.append(
                Finding(
                    rule="unused",
                    severity="warning",
                    name=name,
                    message="defined but never referenced in source",
                    origin=defined[name],
                )
            )

    return result
