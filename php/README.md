# envdoctor (PHP)

[![Packagist](https://img.shields.io/packagist/v/arun-skg/envdoctor.svg?label=Packagist&logo=packagist&logoColor=white)](https://packagist.org/packages/arun-skg/envdoctor)

Native PHP port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, installable via Composer.

See [Why not X?](https://github.com/arun-skg/envdoctor#why-not-x) for how envdoctor
compares to dotenv-linter, gitleaks, and hosted secrets tools.

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
`$_SERVER["X"]`) against those **defined** in `.env` files. Interpolated
references in **Docker Compose** (`${VAR}`), **GitHub Actions** workflows
(`${{ secrets.X }}`, `${{ vars.X }}`, `${{ env.X }}`) and **Kubernetes**
manifests (`${VAR}`) also count as usage, so those files feed the same
missing/undefined and unused checks:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Referenced (in source or infra files) but not defined in any `.env` file |
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
envdoctor init                     # generate .env.example + ENVIRONMENT.md (add --force)
envdoctor fix                      # always (re)generate both files
```

`diff` reports which variable names are only in one environment; `sync` appends
the missing keys to the target `.env` file as empty `KEY=` placeholders — values
are never copied.

`init` / `fix` generate two files at the project root from the union of defined
(`.env*`) and used (source + Compose/Actions/K8s) variable names: `.env.example`
(one `KEY=` per variable) and `ENVIRONMENT.md` (a Defined/Used table). Values are
never written. `init` writes each file only if absent (`--force` overwrites);
`fix` always rewrites both. Both accept `-d/--dir PATH`.

## Schema validation

Add an `envdoctor.schema.json` at your project root to validate `.env` values:

```json
{
  "PORT":  { "type": "integer", "min": 1, "max": 65535 },
  "LEVEL": { "enum": ["debug", "info", "warn", "error"] },
  "TOKEN": { "type": "string", "optional": true }
}
```

Supported rule fields: `type` (string/integer/float/boolean/url/json), `enum`,
`regex`, `min`, `max`, `optional`. Values that fail are reported as
`schema-validation` errors (values are never printed).

## Help make envdoctor smarter

envdoctor is young and its detectors are opinionated. If it missed something or
cried wolf, tell me:

- 🐺 [Report a false positive](https://github.com/arun-skg/envdoctor/issues/new?template=false_positive.yml)
- 🔍 [Report what it missed](https://github.com/arun-skg/envdoctor/issues/new?template=missing_support.yml)

## Other languages

envdoctor ships as a standalone native port for each ecosystem:

- [Node (reference)](..) · [Python](../python) · [Go](../go) · [Ruby](../ruby) · [Java](../java) · [Perl](../perl)
- 📖 Docs: [arun-skg.github.io/envdoctor](https://arun-skg.github.io/envdoctor/)
- Main repository: [github.com/arun-skg/envdoctor](https://github.com/arun-skg/envdoctor)
