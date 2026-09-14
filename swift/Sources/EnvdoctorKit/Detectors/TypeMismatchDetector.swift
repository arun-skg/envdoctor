import Foundation

/// Type mismatch: the same variable is defined with values of incompatible
/// inferred types across environment files. Only variable *types* and
/// locations are reported — never values.
public struct TypeMismatchDetector: Detector {
    public let id = "type-mismatch"
    public let name = "type-mismatch"
    public let description = "The same variable has incompatible inferred types across environment files."

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        var findings: [Finding] = []
        for (name, defs) in index.envDefinitions {
            let typed = defs.filter { $0.value != nil && $0.type != .unknown && $0.value != "" }
            if typed.count < 2 { continue }

            let distinctTypes = Set(typed.map(\.type))
            if distinctTypes.count < 2 { continue }

            let expected = typed.first(where: { $0.environment == "development" })?.type
                ?? mostCommonType(typed)

            for def in typed where def.type != expected {
                findings.append(makeFinding(
                    "type-mismatch", .error, name,
                    "expected: \(expected.label), found: \(def.type.label)",
                    [def.origin]
                ))
            }
        }
        return findings
    }

    private func mostCommonType(_ defs: [Definition]) -> VariableType {
        var counts: [VariableType: Int] = [:]
        for d in defs { counts[d.type, default: 0] += 1 }
        var best = defs[0].type
        var bestCount = -1
        for (type, count) in counts {
            if count > bestCount {
                best = type
                bestCount = count
            }
        }
        return best
    }
}
