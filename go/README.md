# envdoctor (Go)

Native Go implementation of [envdoctor](https://github.com/arun-skg/envdoctor) —
a local-first environment-variable consistency checker, installable as a Go
module so Go projects can use it without Node.

## Install

```bash
go install github.com/arun-skg/envdoctor/go/cmd/envdoctor@latest
```

## Quick start

```bash
envdoctor scan --dir .        # audit; exit 1 on errors
envdoctor scan --strict       # treat warnings as errors too
envdoctor scan --json         # emit findings as a JSON array (no values)
```

## What it detects

Reconciles the variables **used** in Go source (`os.Getenv("X")`,
`os.LookupEnv("X")`) against those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Referenced (source or infra files) but not defined in any `.env` file |
| `duplicates` | error | The same key is defined 2+ times within a single `.env` file |
| `public-prefix` | error | A secret-looking variable is exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `EXPO_PUBLIC_`, `GATSBY_`, `NUXT_PUBLIC_`, `VUE_APP_`, `PUBLIC_`) |
| `type-mismatch` | error | A variable's value has incompatible inferred types across environments (e.g. `PORT=3000` vs `PORT=abc`) |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environment files but missing from others |
| `weak-secret` | warning | A secret-looking variable has a weak, empty, or placeholder value |
| `typo` | warning | A used-but-undefined name closely matches a defined one (likely a typo) |

In addition to Go source, envdoctor scans **Docker Compose**
(`docker-compose.yml` / `compose.yaml`), **GitHub Actions** workflows
(`.github/workflows/*.yml`), and **Kubernetes** manifests (any YAML with both
`apiVersion:` and `kind:`) for referenced variables. Detection is dependency-free
(regex only, no YAML parser): shell-style interpolation `${VAR}` / `$VAR`
(including `${VAR:-default}` forms) across all three, plus
`${{ secrets.X }}`, `${{ vars.X }}`, and `${{ env.X }}` references in Actions.
These references feed the same missing/undefined and unused detectors, so a
variable referenced only in infra files but never defined is flagged, and one
defined and referenced only in infra is not reported unused.

Line and block comments are stripped before scanning. `scan` exits `1` on
errors (or warnings with `--strict`). Variable **values** are used only for
detection and are never printed in any output (human or `--json`). Pass `--json`
to emit a JSON array of findings (each with `rule`, `severity`, `name`,
`message`, `file`, `line`) for machine consumption.

## Development

```bash
cd go
go test ./...
go build ./cmd/envdoctor
```

## Subcommands

Alongside `scan`, every port shares these environment subcommands:

```bash
envdoctor diff <envA> <envB>       # compare two environments (add --json)
envdoctor sync <from> <to>         # copy missing keys (add --dry-run)
envdoctor init [--force]           # generate .env.example + ENVIRONMENT.md
envdoctor fix                      # (re)generate both docs
```

`diff` reports which variable names are only in one environment; `sync` appends
the missing keys to the target `.env` file as empty `KEY=` placeholders — values
are never copied.

### init / fix

Both commands generate two files at the project root from the union of every
variable name (defined in any `.env*` file ∪ referenced in source/infra), sorted
ascending. Values are **never** written.

- `.env.example` — a header comment followed by one `NAME=` line per variable.
- `ENVIRONMENT.md` — a Markdown table of each variable with `Defined`/`Used` columns.

`init` writes each file only if it does not already exist (`--force` overwrites);
`fix` always regenerates both. Every port produces byte-identical files.

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

## Other languages

envdoctor ships as a standalone native port for each ecosystem:

- [Node (reference)](..) · [Python](../python) · [Ruby](../ruby) · [PHP](../php) · [Java](../java) · [Perl](../perl)
- 📖 Docs: [arun-skg.github.io/envdoctor](https://arun-skg.github.io/envdoctor/)
- Main repository: [github.com/arun-skg/envdoctor](https://github.com/arun-skg/envdoctor)
