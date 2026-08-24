# envdoctor Roadmap

envdoctor is a local-first environment-variable consistency checker that reconciles
your `.env` files against your code, Docker Compose, Kubernetes manifests, and CI —
cross-file, fully offline, values never printed. It ships as **native ports** for
seven ecosystems so teams can adopt it in whatever language they already use.

This roadmap is a living document. Most planned work is filed as issues and labelled
[`help wanted`](https://github.com/arun-skg/envdoctor/labels/help%20wanted) —
**contributions are very welcome**. To claim something, comment on the issue.

> New here? Start with [`good first issue`](https://github.com/arun-skg/envdoctor/labels/good%20first%20issue),
> and see [CONTRIBUTING.md](./CONTRIBUTING.md).

---

## ✅ Shipped

- **Core CLI** — `init`, `scan`, `fix`, `diff`, `sync`, `snapshot`.
- **10 detectors** across `.env`, code, Docker Compose, Kubernetes, and GitHub Actions.
- **Output formats** — human, JSON, SARIF.
- **Native ports at full parity** — Node (reference), Python, Go, Ruby, PHP, Perl, Java.
- **Local-first guarantees** — no network, no telemetry, values never printed.

## 🚧 In progress

- **Rust port** — a `rust/` tree exists; bringing it to parity and publishing to crates.io — [#68](https://github.com/arun-skg/envdoctor/issues/68).

## 🗺️ Planned — help wanted

### More native ports
The reference implementation lives in `src/` (TypeScript). A port reaches parity on
all 10 detectors + the six commands + human/JSON/SARIF output, stays offline, and
passes the shared conformance fixtures. See the porting guide ([#90](https://github.com/arun-skg/envdoctor/issues/90)).

- .NET / C# → NuGet — [#69](https://github.com/arun-skg/envdoctor/issues/69)
- Kotlin / JVM — [#70](https://github.com/arun-skg/envdoctor/issues/70)
- Swift → SwiftPM — [#71](https://github.com/arun-skg/envdoctor/issues/71)
- Dart → pub.dev — [#72](https://github.com/arun-skg/envdoctor/issues/72)
- Elixir → Hex — [#73](https://github.com/arun-skg/envdoctor/issues/73)
- Deno / JSR distribution of the TS core — [#74](https://github.com/arun-skg/envdoctor/issues/74)

### Distribution & packaging
- Homebrew formula/tap — [#75](https://github.com/arun-skg/envdoctor/issues/75)
- Docker image on GHCR — [#76](https://github.com/arun-skg/envdoctor/issues/76)
- Prebuilt standalone binaries on Releases — [#77](https://github.com/arun-skg/envdoctor/issues/77)
- Nix flake — [#78](https://github.com/arun-skg/envdoctor/issues/78)
- Shell completions (bash/zsh/fish) — [#79](https://github.com/arun-skg/envdoctor/issues/79)

### CI & editor integrations
- Official GitHub Action (Marketplace) — [#80](https://github.com/arun-skg/envdoctor/issues/80)
- pre-commit framework hook — [#81](https://github.com/arun-skg/envdoctor/issues/81)
- GitLab Code Quality output (`--format gitlab`) — [#82](https://github.com/arun-skg/envdoctor/issues/82)
- JUnit XML output (`--format junit`) — [#83](https://github.com/arun-skg/envdoctor/issues/83)
- VS Code extension (inline diagnostics) — [#84](https://github.com/arun-skg/envdoctor/issues/84)

### Core features
- Watch mode (`scan --watch`) — [#85](https://github.com/arun-skg/envdoctor/issues/85)
- Baseline / suppression file — [#86](https://github.com/arun-skg/envdoctor/issues/86)
- Config JSON Schema + editor autocomplete — [#87](https://github.com/arun-skg/envdoctor/issues/87)
- Expand `--fix` coverage — [#88](https://github.com/arun-skg/envdoctor/issues/88)
- Nested / per-directory config — [#89](https://github.com/arun-skg/envdoctor/issues/89)

### Docs & contributor experience
- **PORTING.md** — the guide for adding a native port — [#90](https://github.com/arun-skg/envdoctor/issues/90)
- **Cross-port conformance suite** — shared fixtures every port runs in CI — [#91](https://github.com/arun-skg/envdoctor/issues/91)
- Docs landing page (`docs/index.html`) — [#92](https://github.com/arun-skg/envdoctor/issues/92)
- `examples/` with runnable sample projects — [#93](https://github.com/arun-skg/envdoctor/issues/93)

---

## Ideas / not yet scoped

Have an idea that isn't here? Open an issue — especially for another language port,
a new detector, or a framework whose public-variable prefix we don't yet recognize.

_Tracking issue: [Roadmap & help wanted](https://github.com/arun-skg/envdoctor/issues/95) (pinned)._
