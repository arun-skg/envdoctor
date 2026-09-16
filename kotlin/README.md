# envdoctor (Kotlin)

Native Kotlin port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, built with Maven
(kotlin-maven-plugin) and packaged as a runnable, shaded CLI jar.

See [Why not X?](https://github.com/arun-skg/envdoctor#why-not-x) for how envdoctor
compares to dotenv-linter, gitleaks, and hosted secrets tools.

## Install

Build the runnable CLI jar from a checkout (JDK 17+ and Maven required):

```bash
cd kotlin
mvn -B package
```

This produces `target/envdoctor-0.1.2.jar` (all dependencies shaded, main
class on the manifest).

## Quick start

```bash
java -jar target/envdoctor-0.1.2.jar scan --dir .        # audit; exit 1 on errors
java -jar target/envdoctor-0.1.2.jar scan --strict       # treat warnings as errors too
java -jar target/envdoctor-0.1.2.jar scan --json         # machine-readable JSON array (no values)
java -jar target/envdoctor-0.1.2.jar scan --no-color     # disable ANSI colors
```

## What it detects

Reconciles variables **used** in Kotlin/Java source (`System.getenv("X")`)
against those **defined** in `.env` files.

It also treats interpolated variables in **Docker Compose**
(`docker-compose.yml`, `compose.yaml`, …), **GitHub Actions** workflows
(`.github/workflows/*.yml`), and **Kubernetes** manifests (any `*.yml`/`*.yaml`
with `apiVersion:` and `kind:`) as *used*. `${VAR}` / `$VAR` interpolation is
recognised everywhere (escaped `$$` is ignored), and in Actions the
`secrets.X` / `vars.X` / `env.X` contexts are recognised too. This feeds the
missing/undefined and unused detectors — values are never read from these
files. Parsing is dependency-free (regex/line scanning, no YAML library).

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code/infra but not defined in any `.env` file |
| `duplicates` | error | Same key defined 2+ times in a single `.env` file |
| `public-prefix` | error | Secret-looking variable exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, …) |
| `type-mismatch` | error | A variable's inferred value type differs across environments |
| `schema-validation` | error | Value violates `envdoctor.schema.json` (type/enum/regex/min/max, required keys) |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environment labels but missing in others |
| `weak-secret` | warning | Secret-looking variable has a weak or placeholder value |
| `typo` | warning | Used-but-undefined name is a near-miss of a defined one |

**Values are never printed** — findings contain rule, severity, name, message,
file and line only.

## Commands

```bash
# Audit (default command; `scan` keyword optional)
java -jar target/envdoctor-0.1.2.jar scan [-d DIR] [--strict] [--no-color] [--json]

# Compare the variable names of two environments (.env vs .env.production, ...)
java -jar target/envdoctor-0.1.2.jar diff default production [-d DIR] [--json]

# Copy missing KEYS between environments as KEY= placeholders (values never copied)
java -jar target/envdoctor-0.1.2.jar sync default production [-d DIR] [--dry-run] [--json]

# Generate .env.example + ENVIRONMENT.md (skips existing files unless --force)
java -jar target/envdoctor-0.1.2.jar init [-d DIR] [--force]

# Regenerate .env.example + ENVIRONMENT.md unconditionally
java -jar target/envdoctor-0.1.2.jar fix [-d DIR]

# Capture this machine's runtime (tool versions, PATH order, OS; never any values)
java -jar target/envdoctor-0.1.2.jar snapshot [--output FILE] [--token] [--json] [--globals]

# Compare two runtime snapshots (token strings or --output JSON files)
java -jar target/envdoctor-0.1.2.jar snapshot-diff <a> <b> [--json]
```

Snapshot tokens are single-line, paste-safe strings
(`envd1:` + base64url(gzip(json))), wire-compatible with the other envdoctor
ports, so a token captured by the TypeScript/Rust/etc. CLI can be diffed here.

## Configuration

- **`.envdoctorignore`** — gitignore-style file at the project root: one
  variable-name glob per line (`#` comments allowed). Matching variables are
  never reported (e.g. `LEGACY_*`, `AWS_*`).
- **`envdoctor.schema.json`** — per-variable validation rules checked during
  `scan`:

  ```json
  {
    "PORT":  { "type": "integer", "min": 1, "max": 65535 },
    "LEVEL": { "enum": ["debug", "info", "warn"] },
    "API":   { "type": "url" },
    "DEBUG": { "type": "boolean", "optional": true }
  }
  ```

## Exit codes

- `0` — no errors (and, without `--strict`, no fatal warnings)
- `1` — errors found (`scan`), or runtime drift detected (`snapshot-diff`)
- `2` — usage error (`snapshot-diff` with an unreadable token/file)

## Development

```bash
mvn -B test      # run the test suite (JUnit 5)
mvn -B package   # build the shaded CLI jar
```

Layout:

- `Scanner.kt` — discovery, dotenv/source/infra parsing, all detectors
- `Snapshot.kt` — runtime capture, token encode/decode, snapshot compare
- `Cli.kt` / `Main.kt` — subcommands and entry point
- `utils/` — dependency-free JSON/TOML/glob helpers shared with the reference
- `models/` — value-type model used by type inference

No network calls at runtime; everything is local-first.
