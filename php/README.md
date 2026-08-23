# envdoctor (PHP)

Native PHP port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, installable via Composer.

## Install

```bash
composer require --dev arun-skg/envdoctor
```

## Quick start

```bash
vendor/bin/envdoctor scan --dir .        # audit; exit 1 on errors
vendor/bin/envdoctor scan --strict       # treat warnings as errors too
vendor/bin/envdoctor scan --json         # emit findings as a JSON array (values never included)
```

## What it detects

Reconciles variables **used** in PHP source (`getenv("X")`, `$_ENV["X"]`,
`$_SERVER["X"]`) against those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `duplicates` | error | Same key defined 2+ times in a single `.env` file |
| `public-prefix` | error | Secret-looking variable exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, …) |
| `type-mismatch` | error | Variable's inferred value type differs across environments (e.g. integer vs string) |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environments but missing from others |
| `weak-secret` | warning | Secret-looking variable has an empty, short, or placeholder value |
| `typo` | warning | Used name closely matches a defined name (likely misspelling) |

Environment labels come from the `.env` filename (`.env`→`default`,
`.env.local`→`local`, `.env.production`→`production`,
`.env.production.local`→`production`); `*.example` files are skipped. Values are
read only to power detection and are **never** included in any output.

Line (`//`, `#`) and block (`/* */`) comments are stripped before scanning.
`scan` exits `1` on errors (or warnings with `--strict`). Pass `--json` to emit
the findings as a JSON array (keys: `rule`, `severity`, `name`, `message`,
`file`, `line`) — still without any values.

## Development

```bash
cd php
php tests/ScannerTest.php   # dependency-free test runner
composer validate --strict
```

## Publishing

Packagist needs `composer.json` at a repo root, so this package is mirrored to a
read-only split repo, [arun-skg/envdoctor-php](https://github.com/arun-skg/envdoctor-php),
where the `php/` subtree sits at the root. Register **that** repo on
[packagist.org](https://packagist.org); its webhook publishes on each push/tag.
The split is kept current automatically by the `PHP Split` workflow (needs a
`SPLIT_REPO_TOKEN` secret). Do not edit the split repo directly — edit `php/` here.

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

- [Node (reference)](..) · [Python](../python) · [Go](../go) · [Ruby](../ruby) · [Java](../java) · [Perl](../perl)
- 📖 Docs: [arun-skg.github.io/envdoctor](https://arun-skg.github.io/envdoctor/)
- Main repository: [github.com/arun-skg/envdoctor](https://github.com/arun-skg/envdoctor)
