import Foundation

/// Undefined-in-source: a variable referenced as `process.env.X` /
/// `import.meta.env.X` in source code that is not defined in any environment
/// file.
public struct UndefinedSourceDetector: Detector {
    public let id = "undefined-in-source"
    public let name = "undefined-in-source"
    public let description = "Used in source code but not defined in any environment file and not documented in .env.example."

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        let defined = Set(index.envDefinitions.map(\.0))
        for (name, origins) in index.sourceUsages {
            if defined.contains(name) { continue }
            findings.append(makeFinding(
                "undefined-in-source", .error, name,
                "used in source code but not defined in any environment file",
                origins
            ))
        }
        return findings
    }
}
