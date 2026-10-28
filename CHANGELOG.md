# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## [1.0.1] - 2026-10-28

### Fixed

- Secret-name heuristic no longer matches `PASS` as a substring, so names like
  `PASSPORT`, `COMPASS`, `BYPASS`, and `PASSENGER` are no longer misreported as
  secrets (which previously produced false `weak-secret` / `public-prefix`
  findings). `PASSWORD`, `PASSWD`, `PASSPHRASE`, and `DB_PASS`-style tokens are
  still detected. The pattern uses no look-around so it remains portable to
  every native port's regex engine.

### Changed

- **Unified the secret-name heuristic across all ports.** Previously the ports
  had diverged into two different patterns (the Node/Dart/.NET/Rust/Swift set
  vs. a `PRIVATE|CREDENTIAL|ACCESS_?KEY|AUTH` set in Python/Ruby/Go/Java/PHP/
  Perl/Elixir/Kotlin), breaking cross-port parity. All 12 ports now use the
  single canonical pattern above, so output is identical across languages
  again. The former `AUTH`/`ACCESS_KEY`/bare-`PRIVATE` matches no longer apply.

## [1.0.0] - 2026-09-30

First stable release. The CLI surface, exit-code contract, detector set, and
output formats (human/JSON/SARIF) are now considered stable across the released
native ports (Node, Python, Ruby, Go, Java, PHP, Rust).

### Fixed

- The dotenv parser already accepted a space after `export`; this extends it to accept tabs and runs of spaces/tabs as the separator.

## [0.1.2] - 2026-08-16

### Added

- Kubernetes manifest support (`env:`, `envFrom:`, ConfigMap/Secret refs).
- `schema-validation` detector and a generated `envdoctor.schema.ts` from `fix`.
- `envdoctor sync <from> <to>` to copy missing keys between environment files.
- `scan --staged` and `scan --since <ref>` to audit only git-changed files.

### Changed

- Comprehensive README refresh (badges, supported formats, contributing) and
  CI examples updated to `actions@v5` / Node 22.

## [0.1.1] - 2026-08-16

### Fixed

- `scan` no longer crashes with `EPERM`/`EACCES` when it encounters an unreadable directory (e.g. running from a home directory that contains `~/.Trash`). Unreadable paths are now skipped.
- Ignore common system directories (`.Trash`, `Library`, `.cache`, `.npm`) during discovery.

## [0.1.0] - 2026-08-16

### Added

- Initial release.
- `envdoctor init` to bootstrap config, `.env.example`, and `ENVIRONMENT.md`.
- `envdoctor scan` to audit environment variables across `.env`, Docker Compose, GitHub Actions, and source code.
- `envdoctor fix` to generate safe documentation and example files.
- `envdoctor diff` to compare variables between two environments.
- Detectors for missing, unused, undefined-in-source, duplicates, environment differences, and type mismatches.
