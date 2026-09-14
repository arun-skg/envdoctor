import Foundation

/// A normalized view of one environment variable across every file in the
/// project. `value` is only ever set for definitions and is an implementation
/// detail: it is never rendered in CLI output and never written into generated
/// files (except non-secret placeholder positions documented per generator).
public struct EnvironmentVariable {
    public var name: String
    /// Raw value, present when at least one origin is a definition with a value.
    public var value: String?
    /// True when the name matches the secret heuristic.
    public var isSecret: Bool
    /// Inferred from `value` when available, else "unknown".
    public var type: VariableType
    /// Every place this name was observed.
    public var origins: [Origin]
    /// Rule ids ignored for this variable via `# envdoctor:ignore <rule>` comments.
    public var ignoreRules: [String]?

    public init(name: String, value: String?, isSecret: Bool, type: VariableType, origins: [Origin], ignoreRules: [String]? = nil) {
        self.name = name
        self.value = value
        self.isSecret = isSecret
        self.type = type
        self.origins = origins
        self.ignoreRules = ignoreRules
    }
}

public func isSecretName(_ name: String) -> Bool {
    // /(SECRET|TOKEN|PASSWORD|PASS|API[_A-Z]*KEY|PRIVATE[_-]?KEY|CREDENTIALS)/i
    let pattern = "(SECRET|TOKEN|PASSWORD|PASS|API[_A-Z]*KEY|PRIVATE[_-]?KEY|CREDENTIALS)"
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
    let range = NSRange(name.startIndex..<name.endIndex, in: name)
    return re.firstMatch(in: name, range: range) != nil
}

/// Build a normalized variable from a name, optional value, and origins.
public func createVariable(_ name: String, _ value: String?, _ origins: [Origin], _ ignoreRules: [String]? = nil) -> EnvironmentVariable {
    EnvironmentVariable(
        name: name,
        value: value,
        isSecret: isSecretName(name),
        type: TypeInfer.inferType(value),
        origins: origins,
        ignoreRules: ignoreRules
    )
}

/// Merge multiple variables with the same name into one, preserving every
/// origin and preferring the first non-empty value.
public func mergeVariables(_ variables: [EnvironmentVariable]) -> [EnvironmentVariable] {
    var byName: [String: EnvironmentVariable] = [:]
    var order: [String] = []
    for v in variables {
        if var existing = byName[v.name] {
            existing.origins.append(contentsOf: v.origins)
            if existing.value == nil, let value = v.value {
                existing.value = value
                existing.type = TypeInfer.inferType(value)
            }
            byName[v.name] = existing
        } else {
            var copy = v
            copy.origins = v.origins
            byName[v.name] = copy
            order.append(v.name)
        }
    }
    return order.compactMap { byName[$0] }
}
