import Foundation

public struct SnapshotDiffArgs {
    public var root: String?
    public var a: String
    public var b: String
    public var json = false

    public init(a: String, b: String) {
        self.a = a
        self.b = b
    }
}

public enum SnapshotDiffCommand {
    /// Resolve a positional arg that may be a token string or a file path.
    private static func loadSnapshot(_ root: String, _ arg: String) throws -> RuntimeSnapshot {
        if arg.trimmingCharacters(in: .whitespaces).hasPrefix("envd1:") {
            return try Token.decodeToken(arg)
        }
        let file = resolvePath(root, arg)
        guard FileManager.default.fileExists(atPath: file) else {
            throw Token.TokenError(description: "Not a snapshot token, and file not found: \(arg)")
        }
        let text = try String(contentsOfFile: file, encoding: .utf8)
        return try Token.parseSnapshotJson(text)
    }

    /// `envdoctor snapshot-diff <a> <b>` — compare two runtime snapshots.
    public static func run(_ args: SnapshotDiffArgs) throws -> Int {
        let root = resolveRoot(args.root)
        let a: RuntimeSnapshot
        let b: RuntimeSnapshot
        do {
            a = try loadSnapshot(root, args.a)
            b = try loadSnapshot(root, args.b)
        } catch let e as Token.TokenError {
            FileHandle.standardError.write("error \(e.description)\n")
            return 2
        } catch {
            FileHandle.standardError.write("error \(error.localizedDescription)\n")
            return 2
        }

        let diff = CompareSnapshots.compare(a, b)

        if args.json {
            print(Json.pretty(diffJsonValue(diff)))
            return diff.equivalent ? 0 : 1
        }

        renderHuman(diff)
        return diff.equivalent ? 0 : 1
    }

    /// `{exitCode, ...diff}` with `undefined` fields omitted, matching the
    /// reference's `JSON.stringify`.
    static func diffJsonValue(_ diff: RuntimeDiff) -> JSONValue {
        var root = JSONObject()
        root.set("exitCode", .int(diff.equivalent ? 0 : 1))

        var osObj = JSONObject()
        osObj.set("status", .string(diff.os.status.rawValue))
        osObj.set("a", .string(diff.os.a))
        osObj.set("b", .string(diff.os.b))
        root.set("os", .object(osObj))

        root.set("tools", .array(diff.tools.map { t in
            var tool = JSONObject()
            tool.set("name", .string(t.name))
            tool.set("status", .string(t.status.rawValue))
            if let a = t.a { tool.set("a", .string(a)) }
            if let b = t.b { tool.set("b", .string(b)) }
            return .object(tool)
        }))
        root.set("pathReordered", .bool(diff.pathReordered))
        root.set("pathOnlyA", .array(diff.pathOnlyA.map { .string($0) }))
        root.set("pathOnlyB", .array(diff.pathOnlyB.map { .string($0) }))
        root.set("globals", .array(diff.globals.map { g in
            var global = JSONObject()
            global.set("ecosystem", .string(g.ecosystem))
            global.set("name", .string(g.name))
            global.set("status", .string(g.status.rawValue))
            if let a = g.a { global.set("a", .string(a)) }
            if let b = g.b { global.set("b", .string(b)) }
            return .object(global)
        }))
        root.set("envFlagOnlyA", .array(diff.envFlagOnlyA.map { .string($0) }))
        root.set("envFlagOnlyB", .array(diff.envFlagOnlyB.map { .string($0) }))
        root.set("equivalent", .bool(diff.equivalent))
        return .object(root)
    }

    private static func renderHuman(_ diff: RuntimeDiff) {
        let title = "RUNTIME DIFF"
        print(title)
        print(rule(title.count * 2) + "\n")
        print("  A → B\n")

        if diff.os.status == .same {
            print("  ✓ OS  \(diff.os.a)\n")
        } else {
            print("  ⚠ OS  \(diff.os.a) → \(diff.os.b)\n")
        }

        print("  Tools")
        for t in diff.tools {
            switch t.status {
            case .same:
                print("  ✓ \(padEnd(t.name, 8)) \(t.a ?? "")")
            case .different:
                print("  ⚠ \(padEnd(t.name, 8)) \(t.a ?? "") → \(t.b ?? "")")
            case .onlyA:
                print("  ❌ \(padEnd(t.name, 8)) missing in B (A: \(t.a ?? ""))")
            case .onlyB:
                print("  ❌ \(padEnd(t.name, 8)) missing in A (B: \(t.b ?? ""))")
            }
        }

        if diff.pathReordered || !diff.pathOnlyA.isEmpty || !diff.pathOnlyB.isEmpty {
            print("\n  PATH")
            if diff.pathReordered {
                print("  ⚠ same entries, different order")
            }
            for p in diff.pathOnlyA {
                print("  ❌ only in A: \(p)")
            }
            for p in diff.pathOnlyB {
                print("  ❌ only in B: \(p)")
            }
        }

        if !diff.globals.isEmpty {
            print("\n  Globals")
            for g in diff.globals {
                let label = "\(g.ecosystem):\(g.name)"
                switch g.status {
                case .different:
                    print("  ⚠ \(label)  \(g.a ?? "") → \(g.b ?? "")")
                case .onlyA:
                    print("  ❌ \(label)  missing in B")
                case .onlyB:
                    print("  ❌ \(label)  missing in A")
                case .same:
                    break
                }
            }
        }

        let status = diff.equivalent ? "✓ runtimes are equivalent" : "✗ runtime drift detected"
        print("\n  \(status)")
    }
}
