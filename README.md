<p align="center">
  <img src="docs/assets/logo.svg" width="120" alt="envdoctor logo" />
</p>

<p align="center">
  <a href="https://www.producthunt.com/products/envdoctor?embed=true&amp;utm_source=badge-featured&amp;utm_medium=badge&amp;utm_campaign=badge-envdoctor" target="_blank" rel="noopener noreferrer"><img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1229915&amp;theme=light&amp;t=1787493130629" alt="envdoctor - ESLint for env vars — catch config bugs before they deploy | Product Hunt" width="250" height="54" /></a>
</p>

# @arunskg/envdoctor

[![npm version](https://img.shields.io/npm/v/@arunskg/envdoctor.svg)](https://www.npmjs.com/package/@arunskg/envdoctor)
[![npm downloads](https://img.shields.io/npm/dm/@arunskg/envdoctor.svg)](https://www.npmjs.com/package/@arunskg/envdoctor)
[![total downloads](https://img.shields.io/npm/dt/@arunskg/envdoctor.svg?label=downloads%20total)](https://www.npmjs.com/package/@arunskg/envdoctor)
[![CI](https://github.com/arun-skg/envdoctor/actions/workflows/ci.yml/badge.svg)](https://github.com/arun-skg/envdoctor/actions/workflows/ci.yml)
[![node](https://img.shields.io/node/v/@arunskg/envdoctor.svg)](https://nodejs.org)
[![license](https://img.shields.io/npm/l/@arunskg/envdoctor.svg)](./LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)
[![Code of Conduct](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](https://github.com/arun-skg/envdoctor?tab=coc-ov-file)

[![PyPI](https://img.shields.io/pypi/v/arun-envdoctor.svg?label=PyPI&logo=pypi&logoColor=white)](https://pypi.org/project/arun-envdoctor/)
[![Gem](https://img.shields.io/gem/v/envdoctor.svg?label=RubyGems&logo=rubygems&logoColor=white)](https://rubygems.org/gems/envdoctor)
[![Packagist](https://img.shields.io/packagist/v/arun-skg/envdoctor.svg?label=Packagist&logo=packagist&logoColor=white)](https://packagist.org/packages/arun-skg/envdoctor)
[![Maven Central](https://img.shields.io/badge/Maven%20Central-0.1.0-C71A36.svg?logo=apachemaven&logoColor=white)](https://central.sonatype.com/artifact/io.github.arun-skg/envdoctor)
[![Go module](https://img.shields.io/badge/Go-v0.1.0-00ADD8.svg?logo=go&logoColor=white)](https://pkg.go.dev/github.com/arun-skg/envdoctor/go)

**The ESLint for environment variables.** envdoctor audits every place your config lives — `.env` files, source code, Docker Compose, Kubernetes manifests, and GitHub Actions — and fails your build *before* a missing key, a dead variable, or a `NEXT_PUBLIC_` secret leak fails your deploy.

```bash
npx @arunskg/envdoctor scan     # Node — or pip / gem / composer / go install, see below
```

Runs **completely locally**: no network calls, no telemetry, variable values never printed. Available as [native ports](#native-ports) for **Node, Python, Go, Ruby, PHP, and Java** — each installable from its own package manager.

📖 **Documentation: [arun-skg.github.io/envdoctor](https://arun-skg.github.io/envdoctor/)** — full guides, per-language references, and examples.

```
┌─────────────────────────────────────────────────────────────────┐
│  ENVIRONMENT AUDIT                                              │
│  ════════════════════════════════════════════════════════════════│
│                                                                 │
│  Missing (error)                                                │
│  ─────────────────────────────────────────────────────────────  │
│  ❌  COMPOSE_ONLY       docker-compose.yml:9   referenced but   │
│                          not defined in any environment file   │
│  ❌  NEW_FEATURE_FLAG   src/index.ts:5         used in source   │
│                          code but not defined in any           │
│                          environment file                      │
│                                                                 │
│  Unused (warning)                                               │
│  ─────────────────────────────────────────────────────────────  │
│  ⚠  DEBUG_MODE          .env:7               defined but never │
│                          referenced anywhere                    │
│                                                                 │
│  Duplicates (error)                                             │
│  ─────────────────────────────────────────────────────────────  │
│  ❌  NODE_ENV            .env:2,12           defined 2 times   │
│                                                                 │
│  Type mismatch (error)                                          │
│  ─────────────────────────────────────────────────────────────  │
│  ❌  PORT                expected: integer · found: string      │
│                                                                 │
│  Summary: 8 files scanned · 15 variables · 4 errors · 16 warns │
└─────────────────────────────────────────────────────────────────┘
```

## Contents

- [Why](#why)
- [Why not X?](#why-not-x)
- [Supported formats](#supported-formats)
- [Installation](#installation)
- [Native ports](#native-ports)
- [Quick start](#quick-start)
- [Help make envdoctor smarter](#-help-make-envdoctor-smarter)
- [Detectors](#detectors)
- [Commands](#commands)
- [Configuration](#configuration)
- [Environment labels](#environment-labels)
- [Output formats](#output-formats)
- [CI integration](#ci-integration)
- [Security](#security)
- [Architecture](#architecture)
- [Development](#development)
- [Contributing](#contributing)
- [Download trends](#download-trends)
- [License](#license)

## Why

Environment drift is a silent class of bug: a variable is used in code but never
documented, defined in `.env` but dead, present in `development` but forgotten in
`production`, or a secret accidentally shipped to the client bundle behind a
`NEXT_PUBLIC_` prefix. `envdoctor` reconciles every place a variable can appear —
`.env` files, Docker Compose, Kubernetes manifests, GitHub Actions, and your
source code — into one normalized model, then runs a suite of detectors over it.

It is **local-first**: everything runs on your machine, nothing is uploaded, and
variable *values* are never printed or written into generated artifacts.

## Why not X?

envdoctor checks the **consistency and hygiene of your env config, locally**. It
deliberately does not try to be a secrets store or a git-history scanner:

| Tool | What it does | How envdoctor differs |
|------|--------------|------------------------|
| **dotenv-linter** | Lints the *syntax* of `.env` files (one ecosystem) | envdoctor reconciles `.env` **against your code, Compose, k8s, and CI** — cross-file, not per-file — with native ports for 6 languages |
| **gitleaks / trufflehog / git-secrets** | Find leaked secret *values* in git history | envdoctor catches the *naming/config mistake* (e.g. a secret behind `VITE_`) **before** it ships — different job, good complement |
| **Doppler / Infisical / dotenv-vault** | Hosted secrets storage and sync | envdoctor stores nothing and never touches the network — it audits the files you already have |
| **checkov / kics** | General IaC security scanning | envdoctor is purpose-built for the env-variable layer, including source-code usage and framework prefixes |
| **ESLint / language linters** | Catch bad code | They stop at `process.env.X` — envdoctor checks whether `X` is defined, typed, documented, and safe to expose |

## Supported formats

| Source | What is read |
|--------|--------------|
| dotenv | `.env`, `.env.local`, `.env.production`, `.env.*` |
| Docker Compose | `environment:` keys and `${VAR}` interpolation |
| Kubernetes | `env:`, `envFrom:`, ConfigMap/Secret manifests |
| GitHub Actions | workflow `env:`, `secrets.*`, `vars.*` |
| Source code | `process.env.X` / `import.meta.env.X` (`.ts/.tsx/.js/.jsx/.mjs/.cjs`) |

## Installation

```bash
# From npm
npm install -g @arunskg/envdoctor

# Or run directly with npx
npx @arunskg/envdoctor scan
```

Using another language? See [native ports](#native-ports) below.

## Native ports

envdoctor is published as a **standalone native implementation** for each
ecosystem — no Node required, no wrappers. Every port scans its own language's
environment idioms, reconciles them against your `.env` files, and exits `1` on
errors so it drops straight into CI.

| Ecosystem | Install | Detects |
|-----------|---------|---------|
| **Node** (reference) | `npm install -g @arunskg/envdoctor` | `process.env.X`, `import.meta.env.X` |
| **Python** ([`python/`](./python)) | `pip install arun-envdoctor` | `os.getenv`, `os.environ[...]`, `os.environ.get` |
| **Go** ([`go/`](./go)) | `go install github.com/arun-skg/envdoctor/go/cmd/envdoctor@latest` | `os.Getenv`, `os.LookupEnv` |
| **Ruby** ([`ruby/`](./ruby)) | `gem install envdoctor` | `ENV["X"]`, `ENV.fetch("X")` |
| **PHP** ([`php/`](./php)) | `composer require --dev arun-skg/envdoctor` | `getenv`, `$_ENV`, `$_SERVER` |
| **Java** ([`java/`](./java)) | [`io.github.arun-skg:envdoctor`](https://central.sonatype.com/artifact/io.github.arun-skg/envdoctor) | `System.getenv("X")` |
| **Perl** ([`perl/`](./perl)) | `cpanm App::Envdoctor` *(pending CPAN release)* | `$ENV{X}` |

All ports share the same CLI shape:

```bash
envdoctor scan --dir .        # audit; exit 1 on errors
envdoctor scan --strict       # treat warnings as errors too
```

> **Note:** the Python distribution is named `arun-envdoctor` on PyPI (the bare
> name is blocked as too similar to an existing project), but the installed
> command and importable package are both `envdoctor`.

Each port has its own README, test suite, and CI workflow, and they are kept
**behaviour-identical** — the same project produces byte-for-byte-equivalent
findings (and `--json` output) in every language. The native ports are now at
**full feature parity** with the Node reference: all **ten detectors**, the
`scan` / `diff` / `sync` / `init` / `fix` subcommands, `--json` output, and
Docker Compose / Kubernetes / GitHub Actions scanning.

| Detector | Node | Python · Go · Ruby · PHP · Perl · Java |
|---|:---:|:---:|
| missing / undefined-in-source | ✅ | ✅ |
| unused | ✅ | ✅ |
| duplicates | ✅ | ✅ |
| public-prefix (secret leak) | ✅ | ✅ |
| weak-secret | ✅ | ✅ |
| typo (did-you-mean) | ✅ | ✅ |
| environment-diff | ✅ | ✅ |
| type-mismatch | ✅ | ✅ |
| schema-validation | ✅ | ✅ |
| `--json` output | ✅ | ✅ |
| `scan` · `diff` · `sync` · `init` · `fix` | ✅ | ✅ |
| Docker Compose · Kubernetes · GitHub Actions sources | ✅ | ✅ |

Schema validation reads an `envdoctor.schema.json` at the project root, e.g.:

```json
{
  "PORT":  { "type": "integer", "min": 1, "max": 65535 },
  "LEVEL": { "enum": ["debug", "info", "warn", "error"] },
  "API":   { "type": "url" },
  "TOKEN": { "type": "string", "optional": true }
}
```

> **Note:** run `npx @arunskg/envdoctor` from your project directory, not from
> inside a checkout of this repo — npx resolves the local package first, whose
> `envdoctor` bin isn't on your PATH, and you'll see `envdoctor: command not
> found`. After a global install, the short `envdoctor` command works anywhere.

## Quick start

```bash
# Bootstrap config + .env.example + ENVIRONMENT.md in your project
envdoctor init

# Scan for issues (exits 1 on errors, 0 on clean)
envdoctor scan

# Compare two environments
envdoctor diff development production

# Copy missing keys from .env to .env.local
envdoctor sync development local

# Scan only files changed on this branch
envdoctor scan --since HEAD

# Generate/update docs (dry-run first)
envdoctor fix --dry-run
envdoctor fix
```

> **Adopting on a legacy project?** Snapshot today's findings and fail CI only
> on *new* ones:
>
> ```bash
> envdoctor scan --write-baseline .envdoctor-baseline.json
> envdoctor scan --baseline .envdoctor-baseline.json   # in CI
> ```

## 🧪 Help make envdoctor smarter

envdoctor is young and its detectors are opinionated. If it **missed
something**, **cried wolf**, or **doesn't understand your framework** (Rails?
Django? SvelteKit? Terraform?), that's a bug *in my priorities* — tell me:

- 🐺 [Report a false positive](https://github.com/arun-skg/envdoctor/issues/new?template=false_positive.yml) — 30 seconds, no values needed
- 🔍 [Report what it missed](https://github.com/arun-skg/envdoctor/issues/new?template=missing_support.yml) — a snippet is enough
- 🗳️ [Vote on language/framework support](https://github.com/arun-skg/envdoctor/discussions) — thumbs-up decides the roadmap

Every report gets a human reply within 48 hours.

## Detectors

| Detector | Severity | What it catches |
|----------|----------|-----------------|
| **missing** | error | Variables referenced in Docker Compose (definitions + `${VAR}` interpolation), Kubernetes, GitHub Actions, or `.env.example` but not defined in any `.env` file |
| **undefined-in-source** | error | `process.env.X` / `import.meta.env.X` in source code with no definition in any `.env` file and not in `.env.example` |
| **unused** | warning | Variables defined in `.env` files but never referenced in source, compose, k8s, or actions |
| **duplicates** | error/warning | Same key defined twice in one file (error); same key across files sharing one environment label (warning) |
| **environment-diff** | warning | Set-membership diffs across environments (e.g. `dev` vs `prod`) |
| **type-mismatch** | error | Incompatible inferred types across environments, or values failing their own inferred type |
| **schema-validation** | error | A value does not match its declared `schema` rule in the config |
| **public-prefix** | error | Secret-looking variable uses a public framework prefix (`NEXT_PUBLIC_*`, `VITE_*`, etc.) and would be exposed to client bundles |
| **weak-secret** | warning | Secret-like variable has a placeholder or very short value |
| **typo** | warning | A referenced name closely matches a defined name and may be a typo |

Any detector can be downgraded or disabled via the [`rules`](#configuration)
config or an [inline ignore](#inline-ignores).

## Commands

### `envdoctor init [--force]`

Bootstraps a project:
- Creates `envdoctor.config.ts` with commented defaults (if missing)
- Generates `.env.example` from discovered variables (if missing)
- Generates `ENVIRONMENT.md` documentation (if missing)

Never overwrites existing files without `--force`.

### `envdoctor scan [options]`

Runs the full audit.

| Option | Description |
|--------|-------------|
| `-d, --dir <path>` | Project root (default: cwd) |
| `--strict` | Treat warnings as errors (exit 1) |
| `--format <format>` | Output format: `human` (default), `json`, or `sarif` |
| `--json` | Alias for `--format json` |
| `--verbose` | Show file:line locations |
| `--only <ruleId>` | Run only specific detector(s), comma-separated |
| `--baseline <path>` | Suppress findings listed in a baseline file |
| `--write-baseline <path>` | Write current findings to a baseline file |
| `--staged` | Only scan files staged for commit |
| `--since <ref>` | Only scan files changed since a git ref (e.g. `HEAD~1`) |

**Exit codes:** `0` = clean, `1` = errors found, `2` = usage/config error

The `--baseline` / `--write-baseline` pair lets you adopt `envdoctor` on a legacy
project: snapshot today's findings, then fail CI only on *new* ones.

`--staged` and `--since` are useful in pre-commit hooks and CI to audit only the
files touched by a changeset instead of the whole repository.

### `envdoctor fix [options]`

Generates/updates safe artifacts based on the audit:
- `.env.example` — all known variables with placeholders (secrets get empty values)
- `ENVIRONMENT.md` — reference table + per-environment sections
- `.github/ENVIRONMENT.md` — checklist of `secrets.*`/`vars.*` for GitHub Actions (if applicable)
- `env.d.ts` — TypeScript ambient declaration for `process.env` variables
- `envdoctor.schema.ts` — inferred Zod-style validation schema from observed values
  (e.g. integer ranges, enum sets). Import and merge it into `envdoctor.config.ts`
  to enable the `schema-validation` detector.

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview changes without writing |
| `--force` | Overwrite without confirmation |

### `envdoctor diff <env1> <env2> [--json]`

Focused comparison between two environments (e.g. `dev prod`, `development production`).
Shows per-variable status: `✓ same`, `⚠ different`, `❌ missing`.

### `envdoctor sync <source> <target>`

Copy missing variable *keys* from one environment file to another without
overwriting existing values. Useful for keeping `.env.local` or `.env.production`
up to date after adding variables to `.env`.

```bash
# Append keys that exist in .env but are missing from .env.local
envdoctor sync development local

# Or by explicit file suffix
envdoctor sync .env .env.production
```

Only keys are copied; values are left untouched so target-specific values and
secrets stay safe.

## Configuration

Configuration is optional — defaults are sensible for most projects. Create
`envdoctor.config.ts` (or `.js`/`.mjs`/`.cjs`, or an `envdoctor` key in
`package.json`):

```ts
export default {
  // Glob patterns for dotenv files
  envFilePatterns: [".env", ".env.*"],

  // Docker Compose file patterns
  composeFilePatterns: ["**/docker-compose*.y*ml", "**/compose*.y*ml"],

  // GitHub Actions workflow patterns
  actionsFilePatterns: [".github/workflows/**/*.y*ml"],

  // Kubernetes manifest patterns
  k8sFilePatterns: ["**/k8s/**/*.y*ml", "**/manifests/**/*.y*ml"],

  // Source file extensions to scan
  sourceExtensions: ["ts", "tsx", "js", "jsx", "mjs", "cjs"],

  // Variable names to ignore entirely (glob patterns, e.g. "AWS_*")
  ignoreVariables: [],

  // File paths to ignore (glob patterns)
  ignoreFiles: [],

  // Explicit environment label → file list overrides
  environments: {
    // development: [".env", ".env.local"],
    // production: [".env.production"],
  },

  // Fail the audit when only warnings are present
  strict: false,

  // Per-detector severity overrides: "error", "warning", or "off"
  rules: {
    // unused: "off",
    // "environment-diff": "error",
  },

  // Per-variable value validation (feeds the schema-validation detector)
  schema: {
    // PORT: { type: "integer", min: 1024 },
    // RATE: { type: "float", min: 0, max: 1 },
    // NODE_ENV: { enum: ["development", "production", "test"] },
    // API_URL: { type: "url" },
    // FEATURE_FLAGS: { type: "json" },
    // Optional variables are allowed to be empty/missing
    // LOG_LEVEL: { type: "string", optional: true },
  },
};
```

### Inline ignores

Suppress a detector for a specific variable with a comment on the preceding line:

```env
# envdoctor:ignore unused
DEBUG_MODE=true

# envdoctor:ignore unused, weak-secret
MY_TOKEN=placeholder
```

## Environment labels

| File | Label |
|------|-------|
| `.env` | `development` (base) |
| `.env.local` | `local` |
| `.env.production` | `production` |
| `.env.<suffix>` | `<suffix>` |
| `.env.example` | `example` (documentation only) |

Aliases: `dev` → `development`, `prod` → `production` for the `diff` command.

## Output formats

### Human (default)
Colorized, sectioned report as shown above.

### JSON (`--json` / `--format json`)
```json
{
  "exitCode": 1,
  "summary": {
    "filesScanned": 8,
    "variablesFound": 15,
    "errors": 4,
    "warnings": 16,
    "infos": 0,
    "total": 20
  },
  "findings": [
    {
      "id": "missing.COMPOSE_ONLY",
      "ruleId": "missing",
      "severity": "error",
      "variable": "COMPOSE_ONLY",
      "message": "referenced but not defined in any environment file",
      "locations": [
        { "file": "docker-compose.yml", "line": 9, "kind": "definition" }
      ]
    }
  ]
}
```

### SARIF (`--format sarif`)
Emits [SARIF 2.1.0](https://sarifweb.azurewebsites.net/) for upload to GitHub
code scanning or any SARIF-aware tool.

## CI integration

```yaml
# .github/workflows/env-audit.yml
name: Environment Audit
on: [push, pull_request]
jobs:
  envdoctor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: '22'
      - run: npx @arunskg/envdoctor scan --strict
```

For code scanning, add `--format sarif` and upload the result with
`github/codeql-action/upload-sarif`.

## Security

- **Values are never printed** to stdout/stderr (even with `--verbose`).
- **Secrets are never written** to generated files (`.env.example`, `ENVIRONMENT.md`, `.github/ENVIRONMENT.md`, `env.d.ts`).
- **No network calls, no telemetry** — everything runs locally.
- Secret heuristic: name matches `/(SECRET|TOKEN|PASSWORD|PASS|API[_A-Z]*KEY|PRIVATE[_-]?KEY|CREDENTIALS)/i`.
- Unreadable directories are skipped rather than aborting the scan.

## Architecture

```
discovery (fast-glob)
    │
    ▼
parsers (dotenv, docker-compose, kubernetes, github-actions, source)
    │
    ▼
normalized ProjectModel (definitions + usages per file)
    │
    ▼
index (buildIndex: maps by name + environment)
    │
    ▼
detectors (missing, undefined-in-source, unused, duplicates,
           environment-diff, type-mismatch, schema-validation,
           public-prefix, weak-secret, typo)
    │
    ▼
AuditResult (Findings + Summary + ExitCode)
    │
    ▼
generators (env-example, environment-doc, env-types, schema, github-actions)
```

Every parser implements a common `Parser` interface and every detector a common
`Detector` interface — new formats and rules can be added without touching the
others.

## Development

```bash
npm install       # install deps
npm test          # run the test suite (vitest)
npm run typecheck # tsc --noEmit
npm run lint      # eslint
npm run build     # tsup → dist/

# Local smoke test
node dist/index.js scan --dir tests/fixtures/sample-project
```

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md)
for the development workflow — please run `npm test`, `npm run lint`, and
`npm run typecheck` before opening a PR. See [CHANGELOG.md](./CHANGELOG.md) for
release history and [SECURITY.md](./SECURITY.md) to report a vulnerability.

Looking for something to work on? The [ROADMAP.md](./ROADMAP.md) tracks planned
work, and issues labelled [`help wanted`](https://github.com/arun-skg/envdoctor/labels/help%20wanted)
and [`good first issue`](https://github.com/arun-skg/envdoctor/labels/good%20first%20issue)
are great starting points — including native ports to new languages.

## Download trends

<details>
<summary>Consolidated downloads across ecosystems, last 90 days (auto-refreshed daily)</summary>

<img src="https://raw.githubusercontent.com/arun-skg/envdoctor/npm-downloads/downloads.svg" alt="Consolidated envdoctor downloads across ecosystems, last 90 days" width="100%">

<sub>Consolidated across ecosystems, auto-refreshed daily by the <a href="./.github/workflows/downloads-chart.yml">Downloads chart</a> workflow. Daily trend lines are shown for npm and PyPI (the registries that publish a time-series); RubyGems and Packagist show current totals. Maven Central and Go do not publish download statistics.</sub>

</details>

## Support

envdoctor is free and MIT-licensed. If it's saved you from a broken deploy,
you can support ongoing development:

- ❤️ [GitHub Sponsors](https://github.com/sponsors/arun-skg)
- ☕ [Buy Me a Coffee](https://buymeacoffee.com/arunskg)

Starring the repo and telling a teammate helps just as much.

## License

[MIT](./LICENSE)
