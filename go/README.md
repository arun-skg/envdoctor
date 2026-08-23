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
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `duplicates` | error | The same key is defined 2+ times within a single `.env` file |
| `public-prefix` | error | A secret-looking variable is exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `EXPO_PUBLIC_`, `GATSBY_`, `NUXT_PUBLIC_`, `VUE_APP_`, `PUBLIC_`) |
| `type-mismatch` | error | A variable's value has incompatible inferred types across environments (e.g. `PORT=3000` vs `PORT=abc`) |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environment files but missing from others |
| `weak-secret` | warning | A secret-looking variable has a weak, empty, or placeholder value |
| `typo` | warning | A used-but-undefined name closely matches a defined one (likely a typo) |

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

- [Node (reference)](..) · [Python](../python) · [Ruby](../ruby) · [PHP](../php) · [Java](../java) · [Perl](../perl)
- 📖 Docs: [arun-skg.github.io/envdoctor](https://arun-skg.github.io/envdoctor/)
- Main repository: [github.com/arun-skg/envdoctor](https://github.com/arun-skg/envdoctor)
