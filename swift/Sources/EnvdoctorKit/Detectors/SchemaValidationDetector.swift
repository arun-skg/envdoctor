import Foundation

/// Schema validation: values in env files are checked against the per-variable
/// rules declared in the config's `schema` section.
public struct SchemaValidationDetector: Detector {
    public let id = "schema-validation"
    public let name = "schema-validation"
    public let description = "A variable value does not match its declared schema."

    public init() {}

    public func detect(_ index: IndexedModel) -> [Finding] {
        let schema = index.model.config.schema
        if schema.isEmpty { return [] }

        // Deterministic emission order: earliest (file, line) of each name's
        // definitions, then name — matching the other ports.
        let sortedEntries = index.envDefinitions.sorted { a, b in
            let ka = sortKey(a.1)
            let kb = sortKey(b.1)
            if ka.path != kb.path { return ka.path < kb.path }
            if ka.line != kb.line { return ka.line < kb.line }
            return a.0 < b.0
        }

        var findings: [Finding] = []
        for (name, defs) in sortedEntries {
            guard let variableSchema = schema[name] else { continue }

            for def in defs {
                guard let error = validateValue(def.value, variableSchema) else { continue }
                findings.append(makeFinding(
                    "schema-validation", .error, name,
                    "does not match schema: \(error)",
                    [def.origin]
                ))
            }
        }
        return findings
    }

    private func sortKey(_ defs: [Definition]) -> (path: String, line: Int) {
        var best: (String, Int)?
        for def in defs {
            let candidate = (def.origin.filePath, def.origin.line ?? Int.max)
            if let current = best {
                let better = candidate.0 == current.0
                    ? candidate.1 < current.1
                    : candidate.0 < current.0
                if better { best = candidate }
            } else {
                best = candidate
            }
        }
        guard let first = best else { return ("", 0) }
        return first
    }

    /// Returns nil when the value is valid, otherwise the error message.
    private func validateValue(_ value: String?, _ schema: VariableSchema) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return (schema.optional ?? false) ? nil : "value is required"
        }

        if let enumValues = schema.enumValues, !enumValues.isEmpty {
            return enumValues.contains(value)
                ? nil
                : "must be one of: \(enumValues.joined(separator: ", "))"
        }

        switch schema.type {
        case .integer:
            guard let n = Int64(value.trimmingCharacters(in: .whitespaces)) else {
                return "must be an integer"
            }
            if let min = schema.min, Double(n) < min { return "must be >= \(Json.jsNumber(min))" }
            if let max = schema.max, Double(n) > max { return "must be <= \(Json.jsNumber(max))" }
            return nil

        case .float:
            guard let n = Double(value.trimmingCharacters(in: .whitespaces)) else {
                return "must be a float"
            }
            if let min = schema.min, n < min { return "must be >= \(Json.jsNumber(min))" }
            if let max = schema.max, n > max { return "must be <= \(Json.jsNumber(max))" }
            return nil

        case .boolean:
            return (value == "true" || value == "false") ? nil : "must be a boolean"

        case .url:
            return (value.hasPrefix("http://") || value.hasPrefix("https://"))
                ? nil
                : "must be a valid URL"

        case .json:
            return (try? JsonParser.parse(value)) != nil ? nil : "must be valid JSON"

        case .regex:
            guard let pattern = schema.regex,
                  let re = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return re.firstMatch(in: value, range: range) != nil ? nil : "must match \(pattern)"

        case .string, .enum, .none:
            return nil
        }
    }
}
