import Foundation

/// Unused: a variable defined in an environment file that is never referenced
/// anywhere. `.env.example` contents are documentation and are excluded.
public struct UnusedDetector: Detector {
    public let id = "unused"
    public let name = "unused"
    public let description = "Defined in an environment file but never referenced in source, docker-compose, GitHub Actions, or Kubernetes manifests."

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        var used = Set(index.usages.map(\.0))
        // A variable that is re-defined in compose/actions/k8s is, by definition, used.
        used.formUnion(index.composeDefinitions.map(\.0))
        used.formUnion(index.actionDefinitions.map(\.0))
        used.formUnion(index.k8sDefinitions.map(\.0))

        var seen = Set<String>()
        for (name, defs) in index.envDefinitions {
            if seen.contains(name) { continue }
            seen.insert(name)
            if used.contains(name) { continue }
            findings.append(makeFinding(
                "unused", .warning, name,
                "defined but never referenced",
                defs.map(\.origin)
            ))
        }
        return findings
    }
}
