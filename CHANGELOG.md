# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

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
