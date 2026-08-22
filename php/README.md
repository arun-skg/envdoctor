# envdoctor (PHP)

Native PHP port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, installable via Composer.

```bash
composer require --dev arun-skg/envdoctor
vendor/bin/envdoctor scan --dir .
```

## What it does

Reconciles variables **used** in PHP source (`getenv("X")`, `$_ENV["X"]`,
`$_SERVER["X"]`) against those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `unused` | warning | Defined in `.env` but never referenced in source |

Line (`//`, `#`) and block (`/* */`) comments are stripped before scanning.
`scan` exits `1` on errors (or warnings with `--strict`). Values are never
printed.

## Development

```bash
cd php
php tests/ScannerTest.php   # dependency-free test runner
composer validate --strict
```

One of several native, per-ecosystem ports; the reference implementation lives
in the [main repository](https://github.com/arun-skg/envdoctor).
