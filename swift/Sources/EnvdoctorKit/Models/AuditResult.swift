import Foundation

public enum Severity: String, CaseIterable {
    case error, warning, info
}

public let severityOrder: [Severity] = [.error, .warning, .info]

/// A single problem found by a detector. `message` is written for humans and
/// must never contain a variable value.
public struct Finding {
    /// Stable id, e.g. `missing.DATABASE_URL` or `type-mismatch.PORT`.
    public var id: String
    /// Detector id that produced this finding.
    public var ruleId: String
    public var severity: Severity
    public var variable: String
    public var message: String
    /// Where the variable was seen; rendered as `path:line`.
    public var locations: [Origin]

    public init(id: String, ruleId: String, severity: Severity, variable: String, message: String, locations: [Origin]) {
        self.id = id
        self.ruleId = ruleId
        self.severity = severity
        self.variable = variable
        self.message = message
        self.locations = locations
    }
}

public struct AuditSummary {
    public var filesScanned: Int
    public var variablesFound: Int
    public var errors: Int
    public var warnings: Int
    public var infos: Int
    public var total: Int
}

public struct AuditResult {
    public var findings: [Finding]
    public var summary: AuditSummary
    /// 0 = clean, 1 = errors, (2 is reserved for usage/config errors).
    public var exitCode: Int
}

public struct ExitContext {
    public var findings: [Finding]
    public var strict: Bool
}

public enum ExitCodes {
    public static let ok = 0
    public static let issues = 1
    public static let usage = 2

    /// Compute the exit code for an audit result given strictness.
    public static func auditExitCode(_ context: ExitContext) -> Int {
        if context.findings.contains(where: { $0.severity == .error }) { return issues }
        if context.strict && context.findings.contains(where: { $0.severity == .warning }) { return issues }
        return ok
    }
}

/// Helper to create a finding with a stable id.
public func makeFinding(_ ruleId: String, _ severity: Severity, _ variable: String, _ message: String, _ locations: [Origin]) -> Finding {
    Finding(id: "\(ruleId).\(variable)", ruleId: ruleId, severity: severity, variable: variable, message: message, locations: locations)
}
