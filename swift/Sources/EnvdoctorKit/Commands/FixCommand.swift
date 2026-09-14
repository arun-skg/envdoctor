import Foundation

public struct FixArgs {
    public var root: String?
    public var dryRun = false
    public var force = false
    public var verbose = false

    public init() {}
}

public enum FixCommand {
    private enum Action {
        case create, update, skip
    }

    private struct PlannedFile {
        var relPath: String
        var action: Action
        var content: String
    }

    /// `envdoctor fix` — run the audit, then regenerate the safe, generated
    /// artifacts: `.env.example`, `ENVIRONMENT.md`, `env.d.ts`,
    /// `envdoctor.schema.ts`, and (when the project uses GitHub Actions
    /// secrets/vars) `.github/ENVIRONMENT.md`.
    public static func run(_ args: FixArgs) throws -> Int {
        let root = resolveRoot(args.root)

        let context = try Pipeline.loadProject(root)
        let audit = Audit.runAudit(context.model, options: AuditOptions(
            strict: false,
            rules: context.config.rules
        ))

        let checklist = GithubActionsGenerator.collectActionsChecklist(context.model)
        let hasActionsRefs = !checklist.secrets.isEmpty || !checklist.vars.isEmpty

        var plans: [PlannedFile] = [
            plan(root, ".env.example", EnvExampleGenerator.generateEnvExample(context.model), args),
            plan(root, "ENVIRONMENT.md", EnvironmentDocGenerator.generateEnvironmentDoc(context.model), args),
            plan(root, "env.d.ts", EnvTypesGenerator.generateEnvTypes(context.model), args),
            plan(root, "envdoctor.schema.ts", SchemaGenerator.generateVariableSchemaTs(context.model), args),
        ]
        if hasActionsRefs {
            plans.append(plan(root, ".github/ENVIRONMENT.md", GithubActionsGenerator.generateActionsChecklist(context.model), args))
        }

        if args.dryRun {
            print("envdoctor fix (dry run)\n")
            for p in plans {
                let marker = p.action == .create ? "+" : (p.action == .update ? "~" : "·")
                print("  \(marker) \(p.relPath)  \(actionLabel(p.action))")
            }
            let pending = plans.filter { $0.action != .skip }.count
            print("\n  \(pending) change\(pending == 1 ? "" : "s") planned")
            return audit.exitCode
        }

        var created = 0
        var updated = 0
        for p in plans {
            if p.action == .skip { continue }
            try writeFile(at: root + "/" + p.relPath, content: p.content)
            if p.action == .create { created += 1 } else { updated += 1 }
        }

        print("envdoctor fix\n")
        for p in plans {
            switch p.action {
            case .skip:
                print("  · skipped \(p.relPath) (exists; use --force to overwrite)")
            case .create:
                print("  ✓ created \(p.relPath)")
            case .update:
                print("  ✓ updated \(p.relPath)")
            }
        }
        print("\n  \(created) created, \(updated) updated · \(audit.summary.errors) error\(audit.summary.errors == 1 ? "" : "s") still present")

        return audit.exitCode
    }

    private static func plan(_ root: String, _ relPath: String, _ content: String, _ args: FixArgs) -> PlannedFile {
        let exists = FileManager.default.fileExists(atPath: root + "/" + relPath)
        if !exists { return PlannedFile(relPath: relPath, action: .create, content: content) }
        if args.force { return PlannedFile(relPath: relPath, action: .update, content: content) }
        return PlannedFile(relPath: relPath, action: .skip, content: content)
    }

    private static func actionLabel(_ action: Action) -> String {
        switch action {
        case .create: return "will create"
        case .update: return "will update"
        case .skip: return "exists"
        }
    }
}
