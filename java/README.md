# envdoctor (Java)

Native Java port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, built with Maven.

```bash
cd java
mvn -B package
java -jar target/envdoctor-0.1.0.jar scan --dir .
```

## What it does

Reconciles variables **used** in Java source (`System.getenv("X")`) against
those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `unused` | warning | Defined in `.env` but never referenced in source |

Line (`//`) and block (`/* */`) comments are stripped before scanning. `scan`
exits `1` on errors (or warnings with `--strict`). Values are never printed.

## Development

```bash
cd java
mvn -B verify          # runs the JUnit 5 suite
# or, without Maven:
javac -d out src/main/java/com/envdoctor/*.java
java -cp out com.envdoctor.Cli scan --dir .
```

One of several native, per-ecosystem ports; the reference implementation lives
in the [main repository](https://github.com/arun-skg/envdoctor).
