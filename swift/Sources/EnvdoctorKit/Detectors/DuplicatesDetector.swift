import Foundation

/// Duplicates: the same variable defined more than once within a single file.
public struct DuplicatesDetector: Detector {
    public let id = "duplicates"
    public let name = "duplicates"
    public let description = "The same variable is defined more than once in a single file."

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        for file in index.model.envFiles {
            var byName: [(String, [Origin])] = []
            for v in file.variables {
                if let idx = byName.firstIndex(where: { $0.0 == v.name }) {
                    byName[idx].1.append(contentsOf: v.origins)
                } else {
                    byName.append((v.name, v.origins))
                }
            }
            for (name, origins) in byName {
                if origins.count < 2 { continue }
                let lines = origins.compactMap(\.line)
                let whereText = lines.isEmpty ? "in this file" : "on lines \(lines.map(String.init).joined(separator: ", "))"
                findings.append(makeFinding(
                    "duplicates", .error, name,
                    "defined \(origins.count) times \(whereText)",
                    origins
                ))
            }
        }
        return findings
    }
}
