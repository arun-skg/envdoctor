# envdoctor (Python)

Native Python port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first consistency checker for environment variables, distributed on PyPI
so Python projects can use it without Node.

## Install

```bash
pip install arun-envdoctor
```

> The PyPI **distribution** is named `arun-envdoctor` (PyPI blocks `envdoctor` as
> too similar to an existing project), but the installed **command** and the
> importable **package** are both still `envdoctor`.

## Quick start

```bash
envdoctor scan --dir .        # audit; exit 1 on errors
envdoctor scan --strict       # treat warnings as errors too
envdoctor scan --json         # emit findings as a JSON array (no values)
```

## What it detects

Reconciles the environment variables **used** in your Python source
(`os.getenv("X")`, `os.environ.get("X")`, `os.environ["X"]`, and the
`from os import environ` forms) against those **defined** in your `.env` files,
then reports:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `duplicates` | error | The same key is defined 2+ times within a single `.env` file |
| `public-prefix` | error | A secret-looking variable is exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `EXPO_PUBLIC_`, `GATSBY_`, `NUXT_PUBLIC_`, `VUE_APP_`, `PUBLIC_`) |
| `type-mismatch` | error | A variable's value has incompatible inferred types across environments (e.g. `PORT=3000` vs `PORT=abc`) |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environment files but missing from others |
| `weak-secret` | warning | A secret-looking variable has a weak, empty, or placeholder value |
| `typo` | warning | A used-but-undefined name closely matches a defined one (likely a typo) |

Comments and docstrings are stripped before scanning, so documented examples
don't cause false positives. Nothing is uploaded and variable **values** are
never printed — they are used only for detection and never appear in any output
(human or `--json`). `envdoctor scan` exits `1` when there are errors (or with
`--strict`, warnings), making it CI-friendly. Pass `--json` to emit a JSON array
of findings (each with `rule`, `severity`, `name`, `message`, `file`, `line`)
for machine consumption.

## Library use

```python
from pathlib import Path
from envdoctor import scan

result = scan(Path("."))
for finding in result.errors:
    print(finding.name, finding.message)
```

## Development

```bash
pip install -e ".[dev]" pytest
pytest
```

## Subcommands

Alongside `scan`, every port shares two environment subcommands:

```bash
envdoctor diff <envA> <envB>       # compare two environments (add --json)
envdoctor sync <from> <to>         # copy missing keys (add --dry-run)
```

`diff` reports which variable names are only in one environment; `sync` appends
the missing keys to the target `.env` file as empty `KEY=` placeholders — values
are never copied.

## Other languages

envdoctor ships as a standalone native port for each ecosystem:

- [Node (reference)](..) · [Go](../go) · [Ruby](../ruby) · [PHP](../php) · [Java](../java) · [Perl](../perl)
- 📖 Docs: [arun-skg.github.io/envdoctor](https://arun-skg.github.io/envdoctor/)
- Main repository: [github.com/arun-skg/envdoctor](https://github.com/arun-skg/envdoctor)
