import Foundation

public struct DiffArgs {
    public var root: String?
    public var envA: String
    public var envB: String
    public var json = false

    public init(envA: String, envB: String) {
        self.envA = envA
        self.envB = envB
    }
}

public enum DiffCommand {
    /// `envdoctor diff <env1> <env2>` — compare variable sets across environments.
    public static func run(_ args: DiffArgs) throws -> Int {
        let root = resolveRoot(args.root)
        let context = try Pipeline.loadProject(root)
        let labelA = normalizeEnvLabel(args.envA)
        let labelB = normalizeEnvLabel(args.envB)

        var availableSet = Set<String>()
        var availableOrder: [String] = []
        for f in context.model.envFiles {
            if let env = f.environment, !env.isEmpty, env != "example", !availableSet.contains(env) {
                availableSet.insert(env)
                availableOrder.append(env)
            }
        }
        let available = availableOrder

        reportParseErrors(context.model, root)

        if !available.contains(labelA) || !available.contains(labelB) {
            if !available.contains(labelA) {
                FileHandle.standardError.write("error Environment \"\(labelA)\" has no files in this project.\n")
            }
            if !available.contains(labelB) {
                FileHandle.standardError.write("error Environment \"\(labelB)\" has no files in this project.\n")
            }
            FileHandle.standardError.write("  Available: \(available.isEmpty ? "none" : available.joined(separator: ", "))\n")
            return 2
        }

        let entries = compareEnvironments(context.model, labelA, labelB)
        let missingCount = entries.filter { !$0.presentInBoth }.count

        if args.json {
            var variables: [JSONValue] = []
            for e in entries {
                var variable = JSONObject()
                variable.set("name", .string(e.name))
                variable.set("status", .string(e.presentInBoth ? "same" : "missing"))
                if e.presentInBoth {
                    variable.set("missingIn", .null)
                } else {
                    variable.set("missingIn", .string(e.presentInA ? labelB : labelA))
                }
                variables.append(.object(variable))
            }
            var rootJson = JSONObject()
            rootJson.set("environments", .array([.string(labelA), .string(labelB)]))
            rootJson.set("exitCode", .int(missingCount > 0 ? 1 : 0))
            rootJson.set("total", .int(entries.count))
            rootJson.set("missing", .int(missingCount))
            rootJson.set("variables", .array(variables))
            print(Json.pretty(.object(rootJson)))
            return missingCount > 0 ? 1 : 0
        }

        let title = "ENVIRONMENT DIFF"
        print(title)
        print(rule(title.count * 2) + "\n")
        print("  \(labelA) → \(labelB)\n")

        for entry in entries {
            if entry.presentInBoth {
                print("  ✓ \(entry.name)  present in both")
            } else if entry.presentInA {
                print("  ❌ \(entry.name)  missing in \(labelB)")
            } else {
                print("  ❌ \(entry.name)  missing in \(labelA)")
            }
        }
        print("\n  Summary: \(entries.count) variables · \(missingCount) missing · \(entries.count - missingCount) present in both")

        return missingCount > 0 ? 1 : 0
    }
}
