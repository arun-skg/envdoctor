# envdoctor (Perl)

Native Perl port of [envdoctor](https://github.com/arun-skg/envdoctor) — a
local-first environment-variable consistency checker.

```bash
cpanm App::Envdoctor
envdoctor scan --dir .
```

Or from a checkout:

```bash
perl Makefile.PL && make && make install
```

## What it does

Reconciles variables **used** in Perl source (`$ENV{X}`, `$ENV{'X'}`,
`$ENV{"X"}`) against those **defined** in `.env` files:

| Rule | Severity | Meaning |
|------|----------|---------|
| `undefined-in-source` | error | Used in code but not defined in any `.env` file |
| `unused` | warning | Defined in `.env` but never referenced in source |

Line comments and POD blocks (`=pod … =cut`) are stripped before scanning.
`scan` exits `1` on errors (or warnings with `--strict`). Values are never
printed. Uses only core modules (`File::Find`, `File::Spec`, `Test::More`).

## Development

```bash
cd perl
prove -Ilib t/
```

One of several native, per-ecosystem ports; the reference implementation lives
in the [main repository](https://github.com/arun-skg/envdoctor).
