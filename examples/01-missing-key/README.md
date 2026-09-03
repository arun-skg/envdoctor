# 01 — Missing key

`DATABASE_URL` is declared in `.env.example` and read by `app.js`, but it was
never added to `.env`. The `missing` detector reports variables that are
referenced (in source code or Compose) but not defined in a real env file.

## Run

```bash
node dist/index.js scan --dir examples/01-missing-key --verbose
```

## Expected output

```
ENVIRONMENT AUDIT
──────────────────────────────────

Missing

  DATABASE_URL  referenced in app.js:3
  · app.js:3

Summary: 3 files scanned · 1 variables · 1 error · 0 warnings
```

## Fix

Add the missing variable to `.env`:

```
DATABASE_URL=postgres://localhost:5432/app
```
