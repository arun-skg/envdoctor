/// Exact `--help` / usage texts mirrored from the reference CLI (commander)
/// so that help output is byte-identical. Each constant ends with a newline.
public enum HelpText {
    public static let topLevel = """
    Usage: envdoctor [options] [command]

    Local-first consistency checker for environment variables. Detects missing,
    unused, duplicate, and mismatched variables across .env files, docker-compose,
    GitHub Actions, and source code.

    Options:
      -V, --version                                 output the version number
      -h, --help                                    display help for command

    Commands:
      init [options]                                Bootstrap envdoctor: config, .env.example, and ENVIRONMENT.md.
      scan [options]                                Scan the project for environment variable inconsistencies.
      fix [options]                                 Generate safe artifacts: .env.example, ENVIRONMENT.md, and a GitHub Actions checklist.
      diff [options] <environment1> <environment2>  Compare environment variable sets across two environments.
      sync [options] <from> <to>                    Copy missing variable keys from one environment file to another with placeholders.
      snapshot [options]                            Capture this machine's live runtime (tool versions, PATH order, globals) as a portable token.
      snapshot-diff [options] <a> <b>               Compare two runtime snapshots (file paths or pasted tokens).
      help [command]                                display help for command

    """

    public static let scan = """
    Usage: envdoctor scan [options]

    Scan the project for environment variable inconsistencies.

    Options:
      -d, --dir <path>         Project directory (default: current directory)
      --strict                 Treat warnings as failures
      --format <format>        Output format: human, json, or sarif (default:
                               "human")
      --json                   Alias for --format json
      --only <rules>           Comma-separated detector ids to run (default: [])
      -v, --verbose            Show file:line locations in the report
      --baseline <path>        Suppress findings matching a baseline file
      --write-baseline <path>  Write current findings to a baseline file
      --staged                 Only scan files with staged git changes
      --since <ref>            Only scan files changed since a git ref
      -h, --help               display help for command

    """

    public static let `init` = """
    Usage: envdoctor init [options]

    Bootstrap envdoctor: config, .env.example, and ENVIRONMENT.md.

    Options:
      --force       Overwrite existing generated files
      --dir <path>  Project directory (default: current directory)
      -h, --help    display help for command

    """

    public static let fix = """
    Usage: envdoctor fix [options]

    Generate safe artifacts: .env.example, ENVIRONMENT.md, and a GitHub Actions
    checklist.

    Options:
      --dir <path>   Project directory (default: current directory)
      --dry-run      Preview changes without writing anything
      --force        Overwrite existing generated files
      -v, --verbose  Show extra detail
      -h, --help     display help for command

    """

    public static let diff = """
    Usage: envdoctor diff [options] <environment1> <environment2>

    Compare environment variable sets across two environments.

    Options:
      --dir <path>  Project directory (default: current directory)
      --json        Emit machine-readable JSON to stdout
      -h, --help    display help for command

    """

    public static let sync = """
    Usage: envdoctor sync [options] <from> <to>

    Copy missing variable keys from one environment file to another with
    placeholders.

    Options:
      -d, --dir <path>  Project directory (default: current directory)
      --dry-run         Preview changes without writing
      -h, --help        display help for command

    """

    public static let snapshot = """
    Usage: envdoctor snapshot [options]

    Capture this machine's live runtime (tool versions, PATH order, globals) as a
    portable token.

    Options:
      -d, --dir <path>     Project directory (default: current directory)
      -o, --output <file>  Write the full snapshot JSON to a file
      --token              Emit a compact base64 token to stdout
      --json               Emit the full snapshot as JSON to stdout
      --globals            Include the global package inventory (slower)
      -h, --help           display help for command

    """

    public static let snapshotDiff = """
    Usage: envdoctor snapshot-diff [options] <a> <b>

    Compare two runtime snapshots (file paths or pasted tokens).

    Options:
      -d, --dir <path>  Project directory (default: current directory)
      --json            Emit machine-readable JSON to stdout
      -h, --help        display help for command

    """

    /// The `generate` subcommand ships in the other native ports but not in the
    /// reference CLI, so this text follows the same commander layout.
    public static let generate = """
    Usage: envdoctor generate [options] <command>

    Print or write a generated artifact from the current project model.

    Options:
      -o, --output <file>  Write the artifact to a file instead of stdout
      -d, --dir <path>     Project directory (default: current directory)
      -h, --help           display help for command

    Commands:
      env-example     Generate a .env.example file.
      env-doc         Generate an ENVIRONMENT.md documentation file.
      env-types       Generate a TypeScript env type declaration file.
      config-schema   Generate the JSON schema for envdoctor config files.
      config-template Generate a starter envdoctor.config template.
      github-actions  Generate a GitHub Actions workflow with secret references.

    """
}

let topLevelHelp = HelpText.topLevel
let scanHelp = HelpText.scan
let initHelp = HelpText.`init`
let fixHelp = HelpText.fix
let diffHelp = HelpText.diff
let syncHelp = HelpText.sync
let snapshotHelp = HelpText.snapshot
let snapshotDiffHelp = HelpText.snapshotDiff
let generateHelp = HelpText.generate
