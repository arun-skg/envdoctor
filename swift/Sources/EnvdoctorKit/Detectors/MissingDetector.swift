import Foundation

/// Missing: a variable that is referenced (in docker-compose, GitHub Actions,
/// or `.env.example`) but defined in no environment file.
public struct MissingDetector: Detector {
    public let id = "missing"
    public let name = "missing"
    public let description = "Referenced in docker-compose, GitHub Actions, or .env.example but not defined in any environment file."

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        let defined = Set(index.envDefinitions.map(\.0))
        // Source usages are the undefined-in-source detector's job.
        let sourceUsed = Set(index.sourceUsages.map(\.0))
        var referenced: [(name: String, origins: [Origin])] = []

        // Compose definitions that are NOT in any .env file are "missing".
        for (name, defs) in index.composeDefinitions {
            if !defined.contains(name), !sourceUsed.contains(name) {
                referenced.append((name, defs.map(\.origin)))
            }
        }
        // Names documented in .env.example but defined nowhere.
        for name in index.exampleNames {
            if !defined.contains(name), !sourceUsed.contains(name) {
                referenced.append((name, []))
            }
        }

        // `${VAR}` interpolation in docker-compose means compose expects the
        // variable to exist.
        for (name, origins) in index.usages {
            let composeOrigins = origins.filter { $0.format == .dockerCompose }
            if composeOrigins.isEmpty { continue }
            if defined.contains(name) || sourceUsed.contains(name) { continue }
            referenced.append((name, composeOrigins))
        }

        var seen = Set<String>()
        for ref in referenced {
            if seen.contains(ref.name) { continue }
            seen.insert(ref.name)
            findings.append(makeFinding(
                "missing", .error, ref.name,
                "referenced but not defined in any environment file",
                ref.origins
            ))
        }
        return findings
    }
}
