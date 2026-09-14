import Foundation

/// Typo detector: pairs names that are referenced but not defined with names
/// that are defined but not referenced, and have a small edit distance.
public struct TypoDetector: Detector {
    public let id = "typo"
    public let name = "typo"
    public let description = "A referenced variable name is very similar to a defined variable name and may be a typo."

    public init() {}

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: a.count + 1), count: b.count + 1)
        for i in 0...b.count { matrix[i][0] = i }
        for j in 0...a.count { matrix[0][j] = j }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        for i in 1...b.count {
            for j in 1...a.count {
                let cost = b[i - 1] == a[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[b.count][a.count]
    }

    private func isLikelyTypo(_ a: String, _ b: String) -> Bool {
        if a == b { return false }
        if a.count < 4 || b.count < 4 { return false }
        let distance = levenshtein(a, b)
        let minLen = min(a.count, b.count)
        if distance == 1 { return true }
        if distance == 2 { return minLen >= 6 }
        if distance == 3 { return minLen >= 10 }
        return false
    }

    public func detect(_ index: IndexedModel) -> [Finding] {
        let defined = Set(index.envDefinitions.map(\.0))
        // JS: new Set([...usages.keys(), ...composeDefinitions.keys(), ...actionDefinitions.keys()])
        // Set insertion order: usages order, then compose defs, then action defs.
        var usedOrder: [String] = []
        var usedSet = Set<String>()
        for name in index.usages.map(\.0) + index.composeDefinitions.map(\.0) + index.actionDefinitions.map(\.0)
        where !usedSet.contains(name) {
            usedSet.insert(name)
            usedOrder.append(name)
        }

        let undefinedNames = usedOrder.filter { !defined.contains($0) }
        let unusedNames = index.envDefinitions.map(\.0).filter { !usedSet.contains($0) }

        let usagesMap = index.usagesMap()

        var findings: [Finding] = []
        var seen = Set<String>()
        for undefinedName in undefinedNames {
            for unusedName in unusedNames {
                if !isLikelyTypo(undefinedName, unusedName) { continue }
                let pairKey = [undefinedName, unusedName].sorted().joined(separator: "\0")
                if seen.contains(pairKey) { continue }
                seen.insert(pairKey)

                let origins = usagesMap[undefinedName] ?? []
                findings.append(makeFinding(
                    "typo", .warning, undefinedName,
                    "did you mean \"\(unusedName)\"? (\(undefinedName) is referenced but not defined, \(unusedName) is defined but unused)",
                    Array(origins.prefix(3))
                ))
            }
        }
        return findings
    }
}
