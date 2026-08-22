# envdoctor (Python)

Native Python port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first consistency checker for environment variables, distributed on PyPI
so Python projects can use it without Node.

```bash
pip install envdoctor
envdoctor scan --dir .
```

## What it does

Reconciles the environment variables **used** in your Python source
(`os.getenv("X")`, `os.environ.get("X")`, `os.environ["X"]`, and the
`from os import environ` forms) against those **defined** in your `.env` files,
then reports:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `unused` | warning | Defined in `.env` but never referenced in source |

Comments and docstrings are stripped before scanning, so documented examples
don't cause false positives. Nothing is uploaded and variable **values** are
never printed.

`envdoctor scan` exits `1` when there are errors (or with `--strict`, warnings),
making it CI-friendly.

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

This package is one of several native, per-ecosystem ports; the reference
implementation and full detector suite live in the
[main repository](https://github.com/arun-skg/envdoctor).
