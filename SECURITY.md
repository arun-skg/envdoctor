# Security Policy

## Supported versions

Only the latest published version of `@arunskg/envdoctor` receives security
updates.

| Version | Supported |
|---------|-----------|
| latest  | ✅        |
| older   | ❌        |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Instead, report privately through GitHub's
[private vulnerability reporting](https://github.com/arun-skg/envdoctor/security/advisories/new)
(Security → Report a vulnerability). If that is unavailable, email the
maintainer at **arunskg12@gmail.com**.

Please include:

- A description of the issue and its impact
- Steps to reproduce (a minimal repository or command is ideal)
- The `envdoctor` version and Node.js version

You can expect an acknowledgement within **7 days**. Once a fix is available it
will be released and the advisory published with credit to the reporter (unless
you prefer to remain anonymous).

## Scope and design notes

`envdoctor` is a **local-first** tool. By design it:

- makes **no network calls** and sends **no telemetry**;
- **never prints variable values** to stdout/stderr, even with `--verbose`;
- **never writes secret values** into generated files (`.env.example`,
  `ENVIRONMENT.md`, `env.d.ts`, `envdoctor.schema.ts`, `.github/ENVIRONMENT.md`).

Reports demonstrating a leak of secret values, or code execution triggered by a
crafted project file (`.env`, compose, Kubernetes manifest, workflow, or source
file) during a scan, are especially in scope.
