# Examples

Self-contained sample projects that intentionally trigger a single
`envdoctor` detector. Each folder is a tiny project you can scan with the
same command documented in its `README.md`, and the output shows the finding
the example demonstrates.

Run any example from the repository root:

```bash
node dist/index.js scan --dir examples/<name> --verbose
```

| Folder | Detector | What it shows |
| --- | --- | --- |
| [`01-missing-key`](./01-missing-key) | `missing` | A variable referenced in code that is not defined in `.env`. |
| [`02-unused-variable`](./02-unused-variable) | `unused` | A variable defined in `.env` that the code never reads. |
| [`03-compose-drift`](./03-compose-drift) | `missing` | A variable present in `docker-compose.yml` but not in `.env`. |
| [`04-weak-secret`](./04-weak-secret) | `weak-secret` | A secret-named variable with a placeholder value. |

Every example returns a non-zero exit code when run with `--strict`:

```bash
node dist/index.js scan --dir examples/01-missing-key --strict --verbose
```

These fixtures are intentionally broken — do not copy them as a starting
point for a real project. Use `envdoctor init` for that.
