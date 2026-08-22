# envdoctor (Ruby)

Native Ruby port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker, packaged as a gem.

```bash
gem install envdoctor
envdoctor scan --dir .
```

## What it does

Reconciles variables **used** in Ruby source (`ENV["X"]`, `ENV['X']`,
`ENV.fetch("X")`) against those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `unused` | warning | Defined in `.env` but never referenced in source |

Comments and `=begin/=end` blocks are stripped before scanning. `scan` exits
`1` on errors (or warnings with `--strict`). Values are never printed.

## Development

```bash
cd ruby
ruby -Ilib test/test_scanner.rb
gem build envdoctor.gemspec
```

One of several native, per-ecosystem ports; the reference implementation lives
in the [main repository](https://github.com/arun-skg/envdoctor).
