import Foundation

public struct EnvDiffEntry {
    public var name: String
    /// Present in both environments.
    public var presentInBoth: Bool
    public var presentInA: Bool
    public var presentInB: Bool
}

/// The set of variable names defined for a given environment label.
public func variablesForEnvironment(_ model: ProjectModel, _ label: String) -> Set<String> {
    var names = Set<String>()
    for file in model.envFiles where file.environment == label {
        for v in file.variables { names.insert(v.name) }
    }
    return names
}

/// Compare two environment labels, returning one entry per variable, sorted
/// with the reference's locale-aware comparator.
public func compareEnvironments(_ model: ProjectModel, _ labelA: String, _ labelB: String) -> [EnvDiffEntry] {
    let a = variablesForEnvironment(model, labelA)
    let b = variablesForEnvironment(model, labelB)
    return Locale.sorted(a.union(b)).map { name in
        EnvDiffEntry(
            name: name,
            presentInBoth: a.contains(name) && b.contains(name),
            presentInA: a.contains(name),
            presentInB: b.contains(name)
        )
    }
}

/// Environment differences: variables that exist in one environment file but
/// are missing from another. Values are never compared — only presence.
public struct EnvironmentDiffDetector: Detector {
    public let id = "environment-diff"
    public let name = "environment-diff"
    public let description = "A variable exists in one environment file but is missing from another."

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        let labels = index.envLabels
        if labels.count < 2 { return [] }
        let reference = labels.contains("development") ? "development" : labels[0]

        for other in labels {
            if other == reference { continue }
            for entry in compareEnvironments(index.model, reference, other) {
                if entry.presentInBoth { continue }
                let missingIn = entry.presentInA ? other : reference
                findings.append(makeFinding(
                    "environment-diff", .warning, entry.name,
                    "\(reference) → \(other) · \(entry.name) missing in \(missingIn)",
                    []
                ))
            }
        }
        return findings
    }
}
