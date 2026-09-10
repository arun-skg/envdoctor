using Envdoctor.Commands;

namespace Envdoctor;

public static class Program
{
    private const string Version = "0.1.2";

    public static int Main(string[] argv)
    {
        var args = new List<string>(argv);

        // Global -C/--root acts as a fallback default; a subcommand-level
        // -C/--root takes precedence.
        string? globalRoot = null;
        for (var i = 0; i < args.Count; i++)
        {
            if (args[i] is "-C" or "--root" && i + 1 < args.Count)
            {
                globalRoot = args[i + 1];
                args.RemoveRange(i, 2);
                i--;
            }
        }

        if (args.Count == 0 || args[0] is "-h" or "--help")
        {
            PrintHelp();
            return args.Count == 0 ? 2 : 0;
        }

        if (args[0] is "-V" or "--version")
        {
            Console.Out.WriteLine($"envdoctor {Version}");
            return 0;
        }

        try
        {
            return args[0] switch
            {
                "scan" => RunScan(args.GetRange(1, args.Count - 1), globalRoot),
                "init" => RunInit(args.GetRange(1, args.Count - 1), globalRoot),
                "fix" => RunFix(args.GetRange(1, args.Count - 1), globalRoot),
                "diff" => RunDiff(args.GetRange(1, args.Count - 1), globalRoot),
                "snapshot" => RunSnapshot(args.GetRange(1, args.Count - 1), globalRoot),
                "snapshot-diff" => RunSnapshotDiff(args.GetRange(1, args.Count - 1), globalRoot),
                "sync" => RunSync(args.GetRange(1, args.Count - 1), globalRoot),
                "generate" => RunGenerate(args.GetRange(1, args.Count - 1), globalRoot),
                "-V" or "--version" => PrintVersion(),
                "-h" or "--help" => PrintHelpOk(),
                _ => UnknownCommand(args[0]),
            };
        }
        catch (UsageException e)
        {
            Console.Error.WriteLine($"error: {e.Message}\n\nUsage: {e.Usage}\n\nFor more information, try '--help'.");
            return 2;
        }
        catch (DirectoryNotFoundException e)
        {
            Console.Error.WriteLine($"error: {e.Message}");
            return 1;
        }
    }

    private static int PrintVersion()
    {
        Console.Out.WriteLine($"envdoctor {Version}");
        return 0;
    }

    private static int PrintHelpOk()
    {
        PrintHelp();
        return 0;
    }

    private static int UnknownCommand(string name)
    {
        Console.Error.WriteLine(
            $"error: unrecognized subcommand '{name}'\n\nUsage: envdoctor [OPTIONS] <COMMAND>\n\nFor more information, try '--help'.");
        return 2;
    }

    private static void PrintHelp()
    {
        Console.Out.WriteLine("""
            Local-first consistency checker for environment variables

            Usage: envdoctor [OPTIONS] <COMMAND>

            Commands:
              scan           Scan for environment variable issues
              init           Initialize a new envdoctor config
              fix            Auto-fix certain issues
              diff           Show differences between environments
              snapshot       Capture runtime snapshot
              snapshot-diff  Compare two runtime snapshots (tokens or JSON files)
              sync           Copy missing keys from one environment file to another
              generate       Generate files from model
              help           Print this message or the help of the given subcommand(s)

            Options:
              -C, --root <ROOT>  Project root (default: current directory)
              -h, --help         Print help
              -V, --version      Print version
            """);
    }

    private sealed class UsageException : Exception
    {
        public string Usage { get; }

        public UsageException(string message, string usage)
            : base(message) => Usage = usage;
    }

    private sealed class ArgCursor
    {
        private readonly List<string> _args;
        private readonly string _usage;
        private int _i;

        public List<string> Positionals { get; } = new();

        public ArgCursor(List<string> args, string usage)
        {
            _args = args;
            _usage = usage;
        }

        public bool Next(out string arg)
        {
            if (_i < _args.Count)
            {
                arg = _args[_i++];
                return true;
            }
            arg = "";
            return false;
        }

        public string RequireValue(string flag)
        {
            if (_i >= _args.Count)
                throw new UsageException(
                    $"a value is required for '{flag} <VALUE>' but none was supplied", _usage);
            return _args[_i++];
        }

        public UsageException Unexpected(string arg) =>
            new($"unexpected argument '{arg}' found", _usage);
    }

    private static void EnsureRootExists(string? root)
    {
        var full = Path.GetFullPath(root ?? ".");
        if (!Directory.Exists(full))
            throw new DirectoryNotFoundException($"No such file or directory: {full}");
    }

    private static int RunScan(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor scan [OPTIONS]";
        var args = new ScanArgs();
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--format":
                    args.Output.Format = ParseFormat(cur.RequireValue(arg), usage);
                    break;
                case "--output" or "-o":
                    args.Output.Output = cur.RequireValue(arg);
                    break;
                case "--strict":
                    args.Output.Strict = true;
                    break;
                case "--verbose" or "-v":
                    args.Verbose = true;
                    break;
                case "--only":
                    args.Only.AddRange(cur.RequireValue(arg).Split(','));
                    break;
                case "--baseline":
                    args.Baseline = cur.RequireValue(arg);
                    break;
                case "--write-baseline":
                    args.WriteBaseline = cur.RequireValue(arg);
                    break;
                case "--staged":
                    args.Staged = true;
                    break;
                case "--since":
                    args.Since = cur.RequireValue(arg);
                    break;
                case "--json":
                    args.Json = true;
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Scan for environment variable issues

                        Usage: envdoctor scan [OPTIONS]

                        Options:
                              --format <FORMAT>
                                  Output format [default: human] [possible values: human, json, sarif]
                              --output <OUTPUT>
                                  Write output to file instead of stdout
                              --strict
                                  Fail on warnings (strict mode)
                          -C, --root <ROOT>
                                  Project root (default: current directory)
                          -v, --verbose
                                  Show file:line locations in the report
                              --only <ONLY>
                                  Restrict the audit to these detector ids (comma-separated)
                              --baseline <BASELINE>
                                  Suppress findings listed in a baseline file
                              --write-baseline <WRITE_BASELINE>
                                  Write the current findings to a baseline file
                              --staged
                                  Only scan files with staged git changes
                              --since <SINCE>
                                  Only scan files changed since a git ref
                              --json
                                  Alias for --format json
                          -h, --help
                                  Print help
                        """);
                    return 0;
                default:
                    throw cur.Unexpected(arg);
            }
        }
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return ScanCommand.Run(args);
    }

    private static int RunInit(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor init [OPTIONS]";
        var args = new InitArgs();
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--force":
                    args.Force = true;
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Initialize a new envdoctor config

                        Usage: envdoctor init [OPTIONS]

                        Options:
                          -C, --root <ROOT>  Project root (default: current directory)
                              --force        Force overwrite existing config
                          -h, --help         Print help
                        """);
                    return 0;
                default:
                    throw cur.Unexpected(arg);
            }
        }
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return InitCommand.Run(args);
    }

    private static int RunFix(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor fix [OPTIONS]";
        var args = new FixArgs();
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--dry-run":
                    args.DryRun = true;
                    break;
                case "--force":
                    args.Force = true;
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Auto-fix certain issues

                        Usage: envdoctor fix [OPTIONS]

                        Options:
                          -C, --root <ROOT>  Project root (default: current directory)
                              --dry-run      Preview changes without writing any files
                              --force        Overwrite files that already exist (default: skip them)
                          -h, --help         Print help
                        """);
                    return 0;
                default:
                    throw cur.Unexpected(arg);
            }
        }
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return FixCommand.Run(args);
    }

    private static int RunDiff(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor diff [OPTIONS] <ENV_A> <ENV_B>";
        var args = new DiffArgs();
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--json":
                    args.Json = true;
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Show differences between environments

                        Usage: envdoctor diff [OPTIONS] <ENV_A> <ENV_B>

                        Arguments:
                          <ENV_A>  First environment (e.g. development, production, or dev/prod aliases)
                          <ENV_B>  Second environment

                        Options:
                          -C, --root <ROOT>  Project root (default: current directory)
                              --json         Print the diff as JSON
                          -h, --help         Print help
                        """);
                    return 0;
                default:
                    if (arg.StartsWith('-'))
                        throw cur.Unexpected(arg);
                    cur.Positionals.Add(arg);
                    break;
            }
        }
        if (cur.Positionals.Count < 2)
            throw new UsageException(
                "the following required arguments were not provided:\n  <ENV_A>\n  <ENV_B>", usage);
        args.EnvA = cur.Positionals[0];
        args.EnvB = cur.Positionals[1];
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return DiffCommand.Run(args);
    }

    private static int RunSnapshot(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor snapshot [OPTIONS]";
        var args = new SnapshotArgs();
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--output" or "-o":
                    args.Output = cur.RequireValue(arg);
                    break;
                case "--token":
                    args.Token = true;
                    break;
                case "--json":
                    args.Json = true;
                    break;
                case "--globals":
                    args.Globals = true;
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Capture runtime snapshot

                        Usage: envdoctor snapshot [OPTIONS]

                        Options:
                          -C, --root <ROOT>      Project root (default: current directory)
                          -o, --output <OUTPUT>  Write the snapshot JSON to a file
                              --token            Print a compact, paste-safe token instead of a human summary
                              --json             Print the raw snapshot JSON
                              --globals          Include the (slow) global package inventory
                          -h, --help             Print help
                        """);
                    return 0;
                default:
                    throw cur.Unexpected(arg);
            }
        }
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return SnapshotCommand.Run(args);
    }

    private static int RunSnapshotDiff(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor snapshot-diff [OPTIONS] <A> <B>";
        var args = new SnapshotDiffArgs();
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--json":
                    args.Json = true;
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Compare two runtime snapshots (tokens or JSON files)

                        Usage: envdoctor snapshot-diff [OPTIONS] <A> <B>

                        Arguments:
                          <A>  First snapshot — a token (`envd1:…`) or a path to a snapshot JSON file
                          <B>  Second snapshot — a token (`envd1:…`) or a path to a snapshot JSON file

                        Options:
                          -C, --root <ROOT>  Project root (default: current directory)
                              --json         Print the diff as JSON
                          -h, --help         Print help
                        """);
                    return 0;
                default:
                    if (arg.StartsWith('-'))
                        throw cur.Unexpected(arg);
                    cur.Positionals.Add(arg);
                    break;
            }
        }
        if (cur.Positionals.Count < 2)
            throw new UsageException(
                "the following required arguments were not provided:\n  <A>\n  <B>", usage);
        args.A = cur.Positionals[0];
        args.B = cur.Positionals[1];
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return SnapshotDiffCommand.Run(args);
    }

    private static int RunSync(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor sync [OPTIONS] <FROM> <TO>";
        var args = new SyncArgs();
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--dry-run":
                    args.DryRun = true;
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Copy missing keys from one environment file to another

                        Usage: envdoctor sync [OPTIONS] <FROM> <TO>

                        Arguments:
                          <FROM>  Source environment (e.g. development, production, or dev/prod aliases)
                          <TO>    Target environment to receive the missing keys

                        Options:
                          -C, --root <ROOT>  Project root (default: current directory)
                              --dry-run      Preview the changes without writing
                          -h, --help         Print help
                        """);
                    return 0;
                default:
                    if (arg.StartsWith('-'))
                        throw cur.Unexpected(arg);
                    cur.Positionals.Add(arg);
                    break;
            }
        }
        if (cur.Positionals.Count < 2)
            throw new UsageException(
                "the following required arguments were not provided:\n  <FROM>\n  <TO>", usage);
        args.From = cur.Positionals[0];
        args.To = cur.Positionals[1];
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return SyncCommand.Run(args);
    }

    private static int RunGenerate(List<string> argv, string? globalRoot)
    {
        const string usage = "envdoctor generate [OPTIONS] <COMMAND>";
        var args = new GenerateArgs();
        string? target = null;
        var cur = new ArgCursor(argv, usage);
        while (cur.Next(out var arg))
        {
            switch (arg)
            {
                case "-C" or "--root":
                    args.Root = cur.RequireValue(arg);
                    break;
                case "--output" or "-o":
                    args.Output = cur.RequireValue(arg);
                    break;
                case "-h" or "--help":
                    Console.Out.WriteLine("""
                        Generate files from model

                        Usage: envdoctor generate [OPTIONS] <COMMAND>

                        Commands:
                          env-example      Generate .env.example
                          env-doc          Generate ENVIRONMENT.md documentation
                          env-types        Generate TypeScript types (env.d.ts)
                          config-schema    Generate JSON schema for configuration
                          config-template  Generate TOML config template
                          github-actions   Generate GitHub Actions workflow snippet

                        Options:
                          -C, --root <ROOT>      Project root (default: current directory)
                          -o, --output <OUTPUT>  Output file (default: stdout)
                          -h, --help             Print help
                        """);
                    return 0;
                default:
                    if (arg.StartsWith('-'))
                        throw cur.Unexpected(arg);
                    if (target is not null)
                        throw cur.Unexpected(arg);
                    target = arg;
                    break;
            }
        }

        args.Target = target switch
        {
            "env-example" => GenerateTarget.EnvExample,
            "env-doc" => GenerateTarget.EnvDoc,
            "env-types" => GenerateTarget.EnvTypes,
            "config-schema" => GenerateTarget.ConfigSchema,
            "config-template" => GenerateTarget.ConfigTemplate,
            "github-actions" => GenerateTarget.GithubActions,
            null => throw new UsageException(
                "the following required arguments were not provided:\n  <COMMAND>", usage),
            _ => throw new UsageException($"unrecognized subcommand '{target}'", usage),
        };
        args.Root ??= globalRoot;
        EnsureRootExists(args.Root);
        return GenerateCommand.Run(args);
    }

    private static OutputFormat ParseFormat(string value, string usage) => value switch
    {
        "human" => OutputFormat.Human,
        "json" => OutputFormat.Json,
        "sarif" => OutputFormat.Sarif,
        _ => throw new UsageException(
            $"invalid value '{value}' for '--format <FORMAT>' [possible values: human, json, sarif]",
            usage),
    };
}
