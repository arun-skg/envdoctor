# 04 — Weak secret

`API_KEY` has a secret-like name, so `envdoctor` inspects its value. `changeme`
is a known placeholder, so the `weak-secret` detector flags it — the kind of
default that ships to production by accident.

## Run

```bash
node dist/index.js scan --dir examples/04-weak-secret --verbose
```

## Expected output

```
ENVIRONMENT AUDIT
──────────────────────────────────

Weak secrets

  API_KEY  API_KEY has a weak or placeholder value in …/examples/04-weak-secret/.env:1

Summary: 3 files scanned · 1 variables · 0 errors · 1 warning
```

> The `message` carries the resolved path to the `.env` file; the `…` stands in
> for the absolute prefix on your machine. The structured `locations` entry
> (`--format json`) reports the portable relative path `.env:1`.

## Fix

Replace the placeholder with a real, high-entropy value:

```
API_KEY=replace-with-a-real-key-here-1234567890
```
