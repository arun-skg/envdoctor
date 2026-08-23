# envdoctor (Java)

Native Java port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, built with Maven and
published to Maven Central as `io.github.arun-skg:envdoctor`.

## Install

Add the dependency (Maven Central):

```xml
<dependency>
  <groupId>io.github.arun-skg</groupId>
  <artifactId>envdoctor</artifactId>
  <version>0.1.0</version>
</dependency>
```

Or build the runnable CLI jar from a checkout:

```bash
cd java
mvn -B package
```

## Quick start

```bash
java -jar target/envdoctor-0.1.0.jar scan --dir .        # audit; exit 1 on errors
java -jar target/envdoctor-0.1.0.jar scan --strict       # treat warnings as errors too
java -jar target/envdoctor-0.1.0.jar scan --json         # machine-readable JSON array (no values)
```

## What it detects

Reconciles variables **used** in Java source (`System.getenv("X")`) against
those **defined** in `.env` files:

It also treats interpolated variables in **Docker Compose**
(`docker-compose.yml`, `compose.yaml`, …), **GitHub Actions** workflows
(`.github/workflows/*.yml`), and **Kubernetes** manifests (any `*.yml`/`*.yaml`
with `apiVersion:` and `kind:`) as *used*. `${VAR}` / `$VAR` interpolation is
recognised everywhere (escaped `$$` is ignored), and in Actions the
`secrets.X` / `vars.X` / `env.X` contexts are recognised too. This feeds the
existing missing/undefined and unused detectors — no new rules, and values are
never read from these files. Parsing is dependency-free (regex/line scanning,
no YAML library).

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `duplicates` | error | Same key defined 2+ times in a single `.env` file |
| `public-prefix` | error | Secret-looking variable exposed to client bundles via a public prefix (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`, …) |
| `type-mismatch` | error | A variable's inferred value type differs across environments (e.g. integer in one `.env`, string in another) |
| `unused` | warning | Defined in `.env` but never referenced in source |
| `environment-diff` | warning | Defined in some environment files but missing from others |
| `weak-secret` | warning | Secret-looking variable has a weak or placeholder value |
| `typo` | warning | Used name closely matches a defined name (likely a misspelling) |

Multiple `.env` files are grouped into environment labels by filename
(`.env`→`default`, `.env.local`→`local`, `.env.production`→`production`,
`.env.production.local`→`production`; `*.example` is skipped). Values are read
only to power detection and are **never** printed in any output.

Add `--json` to emit a JSON array of findings (keys `rule`, `severity`,
`name`, `message`, `file`, `line`) instead of the human report; the exit code
is unchanged. The JSON is hand-built — no third-party dependency.

Line (`//`) and block (`/* */`) comments are stripped before scanning. `scan`
exits `1` on errors (or warnings with `--strict`).

## Development

```bash
cd java
mvn -B verify          # runs the JUnit 5 suite
# or, without Maven:
javac -d out src/main/java/com/envdoctor/*.java
java -cp out com.envdoctor.Cli scan --dir .
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

### init / fix

```bash
envdoctor init [-d DIR] [--force]  # scaffold .env.example + ENVIRONMENT.md
envdoctor fix  [-d DIR]            # (re)generate both files
```

Both generate `.env.example` and `ENVIRONMENT.md` at the project root from the
union of defined (`.env*`) and used (source/infra) variable names, sorted. Only
names are written — values are never emitted. `init` writes each file only when
absent (`--force` overwrites); `fix` always rewrites both. Output is identical
byte-for-byte across every envdoctor port.

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

- [Node (reference)](..) · [Python](../python) · [Go](../go) · [Ruby](../ruby) · [PHP](../php) · [Perl](../perl)
- 📖 Docs: [arun-skg.github.io/envdoctor](https://arun-skg.github.io/envdoctor/)
- Main repository: [github.com/arun-skg/envdoctor](https://github.com/arun-skg/envdoctor)
