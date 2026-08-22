# envdoctor (Go)

Native Go implementation of [envdoctor](https://github.com/arun-skg/envdoctor) —
a local-first environment-variable consistency checker, installable as a Go
module so Go projects can use it without Node.

```bash
go install github.com/arun-skg/envdoctor/go/cmd/envdoctor@latest
envdoctor scan --dir .
```

## What it does

Reconciles the variables **used** in Go source (`os.Getenv("X")`,
`os.LookupEnv("X")`) against those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `unused` | warning | Defined in `.env` but never referenced in source |

Line and block comments are stripped before scanning. `scan` exits `1` on
errors (or warnings with `--strict`). Values are never printed.

## Development

```bash
cd go
go test ./...
go build ./cmd/envdoctor
```

One of several native, per-ecosystem ports; the reference implementation lives
in the [main repository](https://github.com/arun-skg/envdoctor).
