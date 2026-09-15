# envdoctor (Elixir)

Native Elixir port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first consistency checker for environment variables, distributed as an
escript so Elixir projects can use it without Node.

See [Why not X?](https://github.com/arun-skg/envdoctor#why-not-x) for how envdoctor
compares to dotenv-linter, gitleaks, and hosted secrets tools.

## Install

Build the self-contained escript (only Erlang/Elixir required, no runtime deps
beyond what's bundled):

```bash
cd elixir
mix deps.get
mix escript.build
./envdoctor --help
```

Optionally move the binary somewhere on your `$PATH`:

```bash
mv envdoctor ~/.local/bin/
```

## Quick start

```bash
envdoctor scan --dir .        # audit; exit 1 on errors
envdoctor scan --strict       # treat warnings as errors too
envdoctor scan --json         # emit findings as a JSON array (no values)
```

## What it detects

Reconciles the environment variables **used** in your Elixir source
(`System.get_env("X")`, `System.fetch_env("X")`, `System.fetch_env!("X")`)
against those **defined** in your `.env` files, then reports:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Referenced (source or infra files) but not defined in any `.env` file |
| `duplicates` | error | The same key is defined 2+ times within a single `.env` file |
| `public-prefix` | error | A secret-looking variable is exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `EXPO_PUBLIC_`, `GATSBY_`, `NUXT_PUBLIC_`, `VUE_APP_`, `PUBLIC_`) |
| `type-mismatch` | error | A variable's value has incompatible inferred types across environments (e.g. `PORT=3000` vs `PORT=abc`) |
| `schema-validation` | error | A value violates `envdoctor.schema.json` (type, enum, regex, min/max) or a required key is missing |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environment files but missing from others |
| `weak-secret` | warning | A secret-looking variable has a weak, empty, or placeholder value |
| `typo` | warning | A used-but-undefined name closely matches a defined one (likely a typo) |

In addition to Elixir source (`*.ex` / `*.exs`, configurable with
`--ext ex,exs`), envdoctor scans **Docker Compose** (`docker-compose.yml` /
`compose.yaml`), **GitHub Actions** workflows (`.github/workflows/*.yml`), and
**Kubernetes** manifests (any YAML with both `apiVersion:` and `kind:`,
confirmed via yamerl) for referenced variables. Detection is regex-first:
shell-style interpolation `${VAR}` / `$VAR` across all three, plus
`${{ secrets.X }}`, `${{ vars.X }}`, and `${{ env.X }}` references in Actions.
These references feed the same missing/undefined and unused detectors, so a
variable referenced only in infra files but never defined is flagged, and one
defined and referenced only in infra is not reported unused.

Comments and heredocs are stripped before scanning, so documented examples
don't cause false positives. Nothing is uploaded and variable **values** are
never printed — they are used only for detection and never appear in any output
(human or `--json`). `envdoctor scan` exits `1` when there are errors (or with
`--strict`, warnings), making it CI-friendly. Pass `--json` to emit a JSON array
of findings (each with `rule`, `severity`, `name`, `message`, `file`, `line`)
for machine consumption.

## Library use

```elixir
result = Envdoctor.scan(".")
for finding <- Envdoctor.Scanner.ScanResult.errors(result) do
  IO.puts("#{finding.name}: #{finding.message}")
end
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

## Runtime snapshots

`snapshot` captures this machine's live runtime (OS, installed tool versions,
`$PATH` order, non-secret env var **names** only) so two machines can be diffed
to explain "builds on my laptop, fails on the server". Values are never
captured; secret-looking names are dropped entirely.

```bash
envdoctor snapshot                  # human summary
envdoctor snapshot --json           # full JSON
envdoctor snapshot --output a.json  # save to a file
envdoctor snapshot --token          # paste-safe envd1: token (gzip+base64url)
envdoctor snapshot-diff a.json envd1:...   # compare file vs token (add --json)
```

`snapshot-diff` exits `1` when runtime drift is detected.

## Schema validation

Add an `envdoctor.schema.json` at your project root to validate `.env` values:

```json
{
  "PORT":  { "type": "integer", "min": 1, "max": 65535 },
  "LEVEL": { "enum": ["debug", "info", "warn", "error"] },
  "TOKEN": { "type": "string", "optional": true }
}
```

Supported keys per variable: `type` (`string`, `integer`, `float`, `boolean`,
`url`, `json`), `enum`, `regex`, `min`, `max`, `optional`.

## Development

```bash
mix deps.get
mix test
mix escript.build
```

## Exit codes

- `0` — audit ran and found nothing that fails
- `1` — error-severity findings (or warnings under `--strict`), or runtime drift
- `2` — usage error (bad arguments, unreadable snapshot)
