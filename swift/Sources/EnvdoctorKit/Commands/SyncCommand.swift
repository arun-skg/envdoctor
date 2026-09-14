import Foundation

public struct SyncArgs {
    public var root: String?
    public var from: String
    public var to: String
    public var dryRun = false

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public enum SyncCommand {
    /// `envdoctor sync <from> <to>` — copy missing variable keys from one
    /// environment file to another, using placeholder values. Never copies
    /// real secret values.
    public static func run(_ args: SyncArgs) throws -> Int {
        let root = resolveRoot(args.root)
        let fromLabel = normalizeEnvLabel(args.from)
        let toLabel = normalizeEnvLabel(args.to)

        let context = try Pipeline.loadProject(root)
        let model = context.model

        let fromNames = namesForEnvironment(model.envFiles, fromLabel)
        let toNames = namesForEnvironment(model.envFiles, toLabel)

        // The reference sorts with the default (code-unit) comparator.
        let missing = fromNames.filter { !toNames.contains($0) }.sorted()

        if missing.isEmpty {
            print("✓ \(fromLabel) → \(toLabel): nothing to sync")
            return 0
        }

        let targetFile = targetEnvPath(root, toLabel, context.config)
        let targetRel = relativePath(root, targetFile)

        var lines: [String] = ["", "# Synced from \(fromLabel) by envdoctor"]
        for name in missing {
            let placeholder = isSecretName(name) ? "" : "your_\(name.lowercased())"
            lines.append("\(name)=\(placeholder)")
        }
        let append = lines.joined(separator: "\n") + "\n"

        if args.dryRun {
            print("envdoctor sync (dry run)\n")
            print("Would append \(missing.count) key\(missing.count == 1 ? "" : "s") to \(targetRel):")
            for name in missing {
                print("  + \(name)")
            }
            return 0
        }

        let dir = (targetFile as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: targetFile))
        handle.seekToEndOfFile()
        handle.write(Data(append.utf8))
        try handle.close()

        print("envdoctor sync\n")
        print("  ✓ Appended \(missing.count) key\(missing.count == 1 ? "" : "s") to \(targetRel)")
        for name in missing {
            print("    + \(name)")
        }

        return 0
    }

    private static func namesForEnvironment(_ envFiles: [EnvironmentFile], _ label: String) -> Set<String> {
        var names = Set<String>()
        for file in envFiles where file.environment == label {
            for v in file.variables { names.insert(v.name) }
        }
        return names
    }

    private static func targetEnvPath(_ root: String, _ label: String, _ config: EnvdoctorConfig) -> String {
        if let files = config.environments?[label], let first = files.first {
            return resolvePath(root, first)
        }
        if label == "development" { return root + "/.env" }
        return root + "/.env.\(label)"
    }
}
