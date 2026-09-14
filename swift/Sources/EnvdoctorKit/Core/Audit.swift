import Foundation

public struct AuditOptions {
    public var strict: Bool
    /// Restrict the audit to specific detector ids (e.g. `--only missing`).
    public var only: [String]
    /// Per-detector severity overrides.
    public var rules: [String: RuleSeverity]

    public init(strict: Bool, only: [String] = [], rules: [String: RuleSeverity] = [:]) {
        self.strict = strict
        self.only = only
        self.rules = rules
    }
}

/// The audit engine is fully format-agnostic: it takes a `ProjectModel` and
/// returns an `AuditResult`. Detectors run in a stable order and their
/// findings are aggregated; the exit code is derived from severity (and
/// `strict`).
public enum Audit {
    /// All detectors, in a stable order. The audit engine runs them in this
    /// order and the report renders in the same order.
    public static let allDetectors: [Detector] = [
        MissingDetector(),
        UnusedDetector(),
        UndefinedSourceDetector(),
        DuplicatesDetector(),
        EnvironmentDiffDetector(),
        TypeMismatchDetector(),
        PublicPrefixDetector(),
        WeakSecretDetector(),
        TypoDetector(),
        SchemaValidationDetector(),
    ]

    public static func runAudit(_ model: ProjectModel, options: AuditOptions) -> AuditResult {
        let index = buildIndex(model)

        let detectors = options.only.isEmpty
            ? allDetectors
            : allDetectors.filter { options.only.contains($0.id) }

        var findings = detectors.flatMap { $0.detect(index) }

        findings = applyIgnores(findings, model)
        findings = applyRuleSeverities(findings, options.rules)

        let summary = AuditSummary(
            filesScanned: model.allFiles.count,
            variablesFound: Pipeline.distinctVariableCount(model),
            errors: findings.filter { $0.severity == .error }.count,
            warnings: findings.filter { $0.severity == .warning }.count,
            infos: findings.filter { $0.severity == .info }.count,
            total: findings.count
        )

        let exitCode = ExitCodes.auditExitCode(ExitContext(findings: findings, strict: options.strict))
        return AuditResult(findings: findings, summary: summary, exitCode: exitCode)
    }

    /// Build a map of variable name → set of ignored rule ids from inline comments.
    private static func buildIgnoredRulesByName(_ model: ProjectModel) -> [String: Set<String>] {
        var ignored: [String: Set<String>] = [:]
        for file in model.envFiles {
            if file.environment == "example" { continue }
            for v in file.variables {
                guard let ignoreRules = v.ignoreRules, !ignoreRules.isEmpty else { continue }
                ignored[v.name, default: []].formUnion(ignoreRules)
            }
        }
        return ignored
    }

    /// Drop findings that are ignored inline in env files.
    private static func applyIgnores(_ findings: [Finding], _ model: ProjectModel) -> [Finding] {
        let ignored = buildIgnoredRulesByName(model)
        return findings.filter { f in
            guard let rules = ignored[f.variable] else { return true }
            return !rules.contains(f.ruleId)
        }
    }

    /// Apply per-detector severity overrides from config. Disabled rules are dropped.
    private static func applyRuleSeverities(_ findings: [Finding], _ rules: [String: RuleSeverity]) -> [Finding] {
        var result: [Finding] = []
        for var f in findings {
            guard let override = rules[f.ruleId] else {
                result.append(f)
                continue
            }
            if override == .off { continue }
            switch override {
            case .error: f.severity = .error
            case .warning: f.severity = .warning
            case .off: continue
            }
            result.append(f)
        }
        return result
    }

    /// True when a name is defined (has a value) in at least one environment file.
    public static func isDefinedInAnyEnv(_ model: ProjectModel, _ name: String) -> Bool {
        model.envFiles.contains { file in
            file.variables.contains { $0.name == name }
        }
    }

    /// True when a name is documented in `.env.example`.
    public static func isDocumented(_ model: ProjectModel, _ name: String) -> Bool {
        model.envFiles.contains { file in
            file.environment == "example" && file.variables.contains { $0.name == name }
        }
    }
}
