# envdoctor (Swift)

Native Swift port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, distributed via SwiftPM
so Swift (and any) projects can use it without Node.

See [Why not X?](https://github.com/arun-skg/envdoctor#why-not-x) for how envdoctor
compares to dotenv-linter, gitleaks, and hosted secrets tools.

## Install

SwiftPM has no global CLI registry, so install from source:

```bash
git clone https://github.com/arun-skg/envdoctor.git
cd envdoctor/swift
swift build -c release
.build/release/envdoctor --help        # or add .build/release to your PATH
```

Requires Swift 5.9+ (macOS 13+ / Linux). Dependencies: [Yams](https://github.com/jpsim/Yams)
only; everything else is Foundation or hand-rolled. Runs fully offline.

## Quick start

```bash
envdoctor scan -C .           # audit; exit 1 on errors
envdoctor scan --strict       # treat warnings as errors too
envdoctor scan --json         # emit findings as JSON (no values)
```

## What it detects

Reconciles the variables **used** in source (`process.env.X`,
`import.meta.env.X`) against those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Referenced (source or infra files) but not defined in any `.env` file |
| `duplicates` | error | The same key is defined 2+ times within a single `.env` file |
| `public-prefix` | error | A secret-looking variable is exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, `EXPO_PUBLIC_`, `GATSBY_`, `NUXT_PUBLIC_`, `PUBLIC_`, `ASTRO_PUBLIC_`) |
| `type-mismatch` | error | A variable's value has incompatible inferred types across environments (e.g. `PORT=3000` vs `PORT=abc`) |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environment files but missing from others |
| `weak-secret` | warning | A secret-looking variable has a weak, empty, or placeholder value |
| `typo` | warning | A used-but-undefined name closely matches a defined one (likely a typo) |

In addition to source files, envdoctor scans **Docker Compose**
(`docker-compose.yml` / `compose.yaml`), **GitHub Actions** workflows
(`.github/workflows/*.yml`), and **Kubernetes** manifests for referenced
variables. `scan` exits `1` on errors (or warnings with `--strict`). Variable
**values** are used only for detection and are never printed in any output
(human, `--json`, or SARIF). This port is at **byte-identical parity** with the
Node reference for `scan` (human / `--json` / `--format sarif`) and `diff`
output.

## Development

```bash
cd swift
swift build
swift test
```

## Subcommands

Alongside `scan`, every port shares these environment subcommands:

```bash
envdoctor diff <envA> <envB>       # compare two environments (add --json)
envdoctor sync <from> <to>         # copy missing keys (add --dry-run)
envdoctor init [--force]           # generate .env.example + ENVIRONMENT.md
envdoctor fix                      # (re)generate both docs
envdoctor snapshot [--token]       # capture this machine's runtime
envdoctor snapshot-diff <a> <b>    # compare two runtime snapshots
```

`diff` reports which variable names are only in one environment; `sync` appends
the missing keys to the target `.env` file as empty `KEY=` placeholders — values
are never copied.

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
