# 03 — Docker Compose drift

`SENTRY_DSN` is set in `docker-compose.yml` but not in `.env`, so the container
and the local process see different configuration. The `missing` detector
reports variables that appear in Compose but are not defined in `.env`.

## Run

```bash
node dist/index.js scan --dir examples/03-compose-drift --verbose
```

## Expected output

```
ENVIRONMENT AUDIT
──────────────────────────────────

Missing

  SENTRY_DSN  referenced in docker-compose.yml:6
  · docker-compose.yml:6

Summary: 4 files scanned · 2 variables · 1 error · 0 warnings
```

## Fix

Add the variable to `.env` so local and container runs stay in sync:

```
SENTRY_DSN=https://example.invalid/1
```
