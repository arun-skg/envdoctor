import Foundation

public struct SnapshotArgs {
    public var root: String?
    public var output: String?
    public var token = false
    public var json = false
    public var globals = false

    public init() {}
}

public enum SnapshotCommand {
    /// `envdoctor snapshot` — capture this machine's live runtime.
    public static func run(_ args: SnapshotArgs) throws -> Int {
        let root = resolveRoot(args.root)
        let snapshot = Capture.captureSnapshot(globals: args.globals)

        if let output = args.output {
            let dest = resolvePath(root, output)
            try writeFile(at: dest, content: prettySnapshot(snapshot) + "\n")
            FileHandle.standardError.write("✓ Snapshot written to \(output)\n")
        }

        if args.json {
            print(prettySnapshot(snapshot))
            return 0
        }

        if args.token {
            print(Token.encodeToken(snapshot))
            return 0
        }

        // Human summary.
        let title = "RUNTIME SNAPSHOT"
        print(title)
        print(rule(title.count * 2) + "\n")
        print("  OS  \(snapshot.osPlatform)/\(snapshot.osArch) \(snapshot.osRelease)\n")

        print("  Tools")
        if snapshot.tools.isEmpty {
            print("  none detected")
        } else {
            for t in snapshot.tools {
                print("  ✓ \(padEnd(t.tool, 8)) \(t.version)  \(t.resolvedFrom)")
            }
        }

        print("\n  PATH (\(snapshot.path.count) entries)")
        for (i, p) in snapshot.path.prefix(12).enumerated() {
            print("  \(padStart(String(i + 1), 2))  \(p)")
        }
        if snapshot.path.count > 12 {
            print("  … \(snapshot.path.count - 12) more")
        }

        if !snapshot.globals.isEmpty {
            print("\n  Globals")
            for (eco, packages) in snapshot.globals {
                print("  \(eco): \(packages.count) packages")
            }
        } else if !args.globals {
            print("\n  Globals omitted — pass --globals to include the package inventory.")
        }

        print("\n  Share with:  envdoctor snapshot --token   ·   compare with:  envdoctor snapshot-diff <a> <b>")

        return 0
    }

    /// The full snapshot as pretty JSON (`JSON.stringify(snapshot, null, 2)`
    /// key order).
    public static func prettySnapshot(_ snapshot: RuntimeSnapshot) -> String {
        Json.pretty(snapshotJsonValue(snapshot))
    }

    static func snapshotJsonValue(_ snapshot: RuntimeSnapshot) -> JSONValue {
        var globals = JSONObject()
        for (eco, packages) in snapshot.globals {
            globals.set(eco, .array(packages.map { p in
                var pkg = JSONObject()
                pkg.set("name", .string(p.name))
                pkg.set("version", .string(p.version))
                return .object(pkg)
            }))
        }
        var osObj = JSONObject()
        osObj.set("platform", .string(snapshot.osPlatform))
        osObj.set("arch", .string(snapshot.osArch))
        osObj.set("release", .string(snapshot.osRelease))

        var root = JSONObject()
        root.set("schema", .int(snapshot.schema))
        root.set("capturedAt", .string(snapshot.capturedAt))
        root.set("os", .object(osObj))
        root.set("tools", .array(snapshot.tools.map { t in
            var tool = JSONObject()
            tool.set("tool", .string(t.tool))
            tool.set("version", .string(t.version))
            tool.set("resolvedFrom", .string(t.resolvedFrom))
            return .object(tool)
        }))
        root.set("path", .array(snapshot.path.map { .string($0) }))
        root.set("globals", .object(globals))
        root.set("envFlagNames", .array(snapshot.envFlagNames.map { .string($0) }))
        return .object(root)
    }
}
