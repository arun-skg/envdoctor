# 02 — Defined but unused

`LEGACY_TOKEN` is still in `.env` from an old service, but nothing in `app.js`
reads it. The `unused` detector reports variables defined in `.env` that the
code never references — dead config that is safe to delete.

## Run

```bash
node dist/index.js scan --dir examples/02-unused-variable --verbose
```

## Expected output

```
ENVIRONMENT AUDIT
──────────────────────────────────

Defined but unused

  LEGACY_TOKEN  defined in .env:2

Summary: 3 files scanned · 2 variables · 0 errors · 1 warning
```

## Fix

Remove `LEGACY_TOKEN` from `.env` (and from `.env.example` if it is no longer
needed), or add the code that consumes it.
