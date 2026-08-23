"""Command-line entry point for the native Python envdoctor."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .scanner import ScanResult, diff_labels, finding_to_dict, scan, sync_labels

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


def _run_diff(args: argparse.Namespace) -> int:
    root = Path(args.dir).resolve()
    d = diff_labels(root, args.a, args.b)
    if args.json:
        print(json.dumps({"a": args.a, "b": args.b, **d}))
        return 0
    lines = [f"ENVIRONMENT DIFF: {args.a} vs {args.b}", "=" * 40]
    if d["onlyInA"]:
        lines.append(f"Only in {args.a}:")
        lines += [f"  + {k}" for k in d["onlyInA"]]
    if d["onlyInB"]:
        lines.append(f"Only in {args.b}:")
        lines += [f"  + {k}" for k in d["onlyInB"]]
    lines.append(f"Common: {len(d['common'])} variable(s)")
    print("\n".join(lines))
    return 0


def _run_sync(args: argparse.Namespace) -> int:
    root = Path(args.dir).resolve()
    added = sync_labels(root, args.from_, args.to, dry_run=args.dry_run)
    if args.json:
        print(json.dumps({"from": args.from_, "to": args.to, "added": added, "dryRun": args.dry_run}))
        return 0
    if not added:
        print("Already in sync.")
        return 0
    verb = "Would sync" if args.dry_run else "Synced"
    print(f"{verb} {len(added)} variable(s) from {args.from_} to {args.to}:")
    print("\n".join(f"  + {k}" for k in added))
    return 0


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
    scan_cmd.add_argument("--json", action="store_true", help="Emit findings as JSON")

    diff_cmd = sub.add_parser("diff", help="Compare two environments")
    diff_cmd.add_argument("a")
    diff_cmd.add_argument("b")
    diff_cmd.add_argument("-d", "--dir", default=".", help="Project root (default: cwd)")
    diff_cmd.add_argument("--json", action="store_true", help="Emit the diff as JSON")

    sync_cmd = sub.add_parser("sync", help="Copy missing keys between environments")
    sync_cmd.add_argument("from_", metavar="from")
    sync_cmd.add_argument("to")
    sync_cmd.add_argument("-d", "--dir", default=".", help="Project root (default: cwd)")
    sync_cmd.add_argument("--dry-run", action="store_true", help="Show changes without writing")
    sync_cmd.add_argument("--json", action="store_true", help="Emit the result as JSON")

    args = parser.parse_args(argv)

    if args.command == "diff":
        return _run_diff(args)
    if args.command == "sync":
        return _run_sync(args)
    if args.command != "scan":
        parser.print_help()
        return 0

    root = Path(args.dir).resolve()
    result = scan(root)
    if args.json:
        print(json.dumps([finding_to_dict(f, root) for f in result.findings]))
    else:
        use_color = not args.no_color and sys.stdout.isatty()
        print(format_report(result, root, use_color))

    if result.errors or (args.strict and result.warnings):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
