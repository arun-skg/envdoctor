import Foundation

/// The envdoctor CLI entry point. Mirrors the reference CLI's observable
/// behavior: byte-identical help/version/error text and exit codes, plus the
/// `-C/--root` global flag and the `generate` subcommand from the other
/// native ports.
public enum Program {
    public static let version = "0.1.2"

    public static func main(_ argv: [String]) -> Int {
        var args = Array(argv)

        // Global -C/--root acts as a fallback default; a subcommand-level
        // -C/--root takes precedence.
        var globalRoot: String?
        var i = 0
        while i < args.count {
            if args[i] == "-C" || args[i] == "--root" {
                guard i + 1 < args.count else {
                    FileHandle.standardError.write("error: unknown option '\(args[i])'\n")
                    return 2
                }
                globalRoot = args[i + 1]
                args.removeSubrange(i...(i + 1))
                continue
            }
            i += 1
        }

        if args.isEmpty {
            FileHandle.standardError.write(topLevelHelp)
            return 2
        }

        switch args[0] {
        case "-h", "--help":
            print(topLevelHelp, terminator: "")
            return 0
        case "-V", "--version", "--version".uppercased():
            print(version)
            return 0
        case "help":
            if args.count > 1 {
                return runSubcommandHelp(args[1])
            }
            print(topLevelHelp, terminator: "")
            return 0
        case "scan":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runScan)
        case "init":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runInit)
        case "fix":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runFix)
        case "diff":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runDiff)
        case "sync":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runSync)
        case "snapshot":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runSnapshot)
        case "snapshot-diff":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runSnapshotDiff)
        case "generate":
            return run(args: Array(args.dropFirst()), globalRoot: globalRoot, body: runGenerate)
        default:
            FileHandle.standardError.write("error: unknown command '\(args[0])'\n")
            return 2
        }
    }

    // MARK: - Subcommand bodies (argv excludes the subcommand name)

    private static func run(args: [String], globalRoot: String?, body: ([String], String?) -> Int) -> Int {
        body(args, globalRoot)
    }

    private static func runScan(_ argv: [String], _ globalRoot: String?) -> Int {
        var args = ScanArgs()
        var root: String? = globalRoot
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "--format":
                let value = cur.requireValue(arg)
                guard let format = OutputFormat(rawValue: value) else {
                    FileHandle.standardError.write("error: unknown format \"\(value)\"\n")
                    return 2
                }
                args.format = format
            case "--strict":
                args.strict = true
            case "-v", "--verbose":
                args.verbose = true
            case "--only":
                args.only = cur.requireValue(arg).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case "--baseline":
                args.baseline = cur.requireValue(arg)
            case "--write-baseline":
                args.writeBaseline = cur.requireValue(arg)
            case "--staged":
                args.staged = true
            case "--since":
                args.since = cur.requireValue(arg)
            case "--json":
                args.format = .json
            case "-o", "--output":
                args.output = cur.requireValue(arg)
            case "-h", "--help":
                print(scanHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                FileHandle.standardError.write("error: unknown argument '\(arg)'\n")
                return 2
            }
        }
        args.root = root
        do {
            return try ScanCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runInit(_ argv: [String], _ globalRoot: String?) -> Int {
        var args = InitArgs()
        var root: String? = globalRoot
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "--force":
                args.force = true
            case "-h", "--help":
                print(initHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                FileHandle.standardError.write("error: unknown argument '\(arg)'\n")
                return 2
            }
        }
        args.root = root
        do {
            return try InitCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runFix(_ argv: [String], _ globalRoot: String?) -> Int {
        var args = FixArgs()
        var root: String? = globalRoot
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "--dry-run":
                args.dryRun = true
            case "--force":
                args.force = true
            case "-v", "--verbose":
                args.verbose = true
            case "-h", "--help":
                print(fixHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                FileHandle.standardError.write("error: unknown argument '\(arg)'\n")
                return 2
            }
        }
        args.root = root
        do {
            return try FixCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runDiff(_ argv: [String], _ globalRoot: String?) -> Int {
        var root: String? = globalRoot
        var json = false
        var positionals: [String] = []
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "--json":
                json = true
            case "-h", "--help":
                print(diffHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                positionals.append(arg)
            }
        }
        if positionals.isEmpty {
            FileHandle.standardError.write("error: missing required argument 'environment1'\n")
            return 1
        }
        if positionals.count == 1 {
            FileHandle.standardError.write("error: missing required argument 'environment2'\n")
            return 1
        }
        var args = DiffArgs(envA: positionals[0], envB: positionals[1])
        args.root = root
        args.json = json
        do {
            return try DiffCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runSync(_ argv: [String], _ globalRoot: String?) -> Int {
        var root: String? = globalRoot
        var dryRun = false
        var positionals: [String] = []
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "--dry-run":
                dryRun = true
            case "-h", "--help":
                print(syncHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                positionals.append(arg)
            }
        }
        if positionals.isEmpty {
            FileHandle.standardError.write("error: missing required argument 'from'\n")
            return 1
        }
        if positionals.count == 1 {
            FileHandle.standardError.write("error: missing required argument 'to'\n")
            return 1
        }
        var args = SyncArgs(from: positionals[0], to: positionals[1])
        args.root = root
        args.dryRun = dryRun
        do {
            return try SyncCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runSnapshot(_ argv: [String], _ globalRoot: String?) -> Int {
        var args = SnapshotArgs()
        var root: String? = globalRoot
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "-o", "--output":
                args.output = cur.requireValue(arg)
            case "--token":
                args.token = true
            case "--json":
                args.json = true
            case "--globals":
                args.globals = true
            case "-h", "--help":
                print(snapshotHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                FileHandle.standardError.write("error: unknown argument '\(arg)'\n")
                return 2
            }
        }
        args.root = root
        do {
            return try SnapshotCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runSnapshotDiff(_ argv: [String], _ globalRoot: String?) -> Int {
        var root: String? = globalRoot
        var json = false
        var positionals: [String] = []
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "--json":
                json = true
            case "-h", "--help":
                print(snapshotDiffHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                positionals.append(arg)
            }
        }
        if positionals.isEmpty {
            FileHandle.standardError.write("error: missing required argument 'a'\n")
            return 1
        }
        if positionals.count == 1 {
            FileHandle.standardError.write("error: missing required argument 'b'\n")
            return 1
        }
        var args = SnapshotDiffArgs(a: positionals[0], b: positionals[1])
        args.root = root
        args.json = json
        do {
            return try SnapshotDiffCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runGenerate(_ argv: [String], _ globalRoot: String?) -> Int {
        var root: String? = globalRoot
        var output: String?
        var target: String?
        var cur = ArgCursor(argv)
        while let arg = cur.next() {
            switch arg {
            case "-d", "--dir", "-C", "--root":
                root = cur.requireValue(arg)
            case "-o", "--output":
                output = cur.requireValue(arg)
            case "-h", "--help":
                print(generateHelp, terminator: "")
                return 0
            default:
                if arg.hasPrefix("-") {
                    FileHandle.standardError.write("error: unknown option '\(arg)'\n")
                    return 2
                }
                if target != nil {
                    FileHandle.standardError.write("error: unknown argument '\(arg)'\n")
                    return 2
                }
                target = arg
            }
        }
        guard let target else {
            FileHandle.standardError.write("error: missing required argument 'command'\n")
            return 1
        }
        guard let generateTarget = GenerateTarget(rawValue: target) else {
            FileHandle.standardError.write("error: unknown command '\(target)'\n")
            return 2
        }
        var args = GenerateArgs(target: generateTarget)
        args.root = root
        args.output = output
        do {
            return try GenerateCommand.run(args)
        } catch {
            FileHandle.standardError.write("error: \(error.localizedDescription)\n")
            return 2
        }
    }

    private static func runSubcommandHelp(_ name: String) -> Int {
        switch name {
        case "scan": print(scanHelp, terminator: "")
        case "init": print(initHelp, terminator: "")
        case "fix": print(fixHelp, terminator: "")
        case "diff": print(diffHelp, terminator: "")
        case "sync": print(syncHelp, terminator: "")
        case "snapshot": print(snapshotHelp, terminator: "")
        case "snapshot-diff": print(snapshotDiffHelp, terminator: "")
        case "generate": print(generateHelp, terminator: "")
        default:
            FileHandle.standardError.write("error: unknown help topic '\(name)'\n")
            return 2
        }
        return 0
    }

    private struct ArgCursor {
        private let args: [String]
        private var i = 0

        init(_ args: [String]) {
            self.args = args
        }

        mutating func next() -> String? {
            guard i < args.count else { return nil }
            defer { i += 1 }
            return args[i]
        }

        mutating func requireValue(_ flag: String) -> String {
            // Defer the bounds check to the caller via empty string sentinel;
            // all callers treat a missing value as a usage error.
            guard i < args.count else { return "" }
            defer { i += 1 }
            return args[i]
        }
    }
}
