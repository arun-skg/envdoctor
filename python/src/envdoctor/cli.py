"""Command-line entry point for the native Python envdoctor."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .scanner import ScanResult, scan

_RED = "\033[31m"
_YELLOW = "\033[33m"
_DIM = "\033[2m"
_RESET = "\033[0m"


def _color(text: str, code: str, use_color: bool) -> str:
    return f"{code}{text}{_RESET}" if use_color else text


def format_report(result: ScanResult, root: Path, use_color: bool = True) -> str:
    lines = ["ENVIRONMENT AUDIT", "=" * 40, ""]
    if not result.findings:
        lines.append("No issues found.")
        return "\n".join(lines)

    if result.errors:
        lines.append(_color("Errors", _RED, use_color))
        for f in result.errors:
            loc = ""
            if f.origin:
                loc = f" {_color(f'{f.origin.file.relative_to(root)}:{f.origin.line}', _DIM, use_color)}"
            lines.append(f"  x {f.name}{loc}  {f.message}")
        lines.append("")

    if result.warnings:
        lines.append(_color("Warnings", _YELLOW, use_color))
        for f in result.warnings:
            loc = ""
            if f.origin:
                loc = f" {_color(f'{f.origin.file.relative_to(root)}:{f.origin.line}', _DIM, use_color)}"
            lines.append(f"  ! {f.name}{loc}  {f.message}")
        lines.append("")

    lines.append(
        f"Summary: {len(result.errors)} error(s), {len(result.warnings)} warning(s)"
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="envdoctor",
        description="Local-first consistency checker for environment variables.",
    )
    sub = parser.add_subparsers(dest="command")
    scan_cmd = sub.add_parser("scan", help="Audit environment variables")
    scan_cmd.add_argument("-d", "--dir", default=".", help="Project root (default: cwd)")
    scan_cmd.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    scan_cmd.add_argument("--no-color", action="store_true", help="Disable ANSI color")
    args = parser.parse_args(argv)

    if args.command != "scan":
        parser.print_help()
        return 0

    root = Path(args.dir).resolve()
    result = scan(root)
    use_color = not args.no_color and sys.stdout.isatty()
    print(format_report(result, root, use_color))

    if result.errors or (args.strict and result.warnings):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
