import Foundation

/// The basic value types envdoctor can infer from a variable's value.
public enum VariableType: String, CaseIterable {
    case integer, float, boolean, url, json, string, unknown

    /// Human-readable label used in CLI output and generated docs.
    public var label: String { rawValue }
}

/// JS `String(value)` for the scalar shapes YAML resolution produces.
public func jsString(_ value: Any?) -> String {
    switch value {
    case .none: return "null"
    case .some(let v):
        switch v {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let i as Int64: return String(i)
        case let d as Double: return Json.jsNumber(d)
        case let list as [Any?]: return list.map { jsString($0) }.joined(separator: ",")
        case is [String: Any?]: return "[object Object]"
        default: return String(describing: v)
        }
    }
}

public enum TypeInfer {
    private static let integerRe = try! NSRegularExpression(pattern: #"^-?\d+$"#)
    private static let floatRe = try! NSRegularExpression(pattern: #"^-?\d+\.\d+([eE][+-]?\d+)?$"#)
    private static let booleanRe = try! NSRegularExpression(pattern: #"^(true|false|TRUE|FALSE)$"#)
    private static let urlRe = try! NSRegularExpression(pattern: #"^https?://\S+$"#, options: [.caseInsensitive])

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.firstMatch(in: s, range: range) != nil
    }

    /// Infer the basic type of a variable value. Ordering matters: a value like
    /// "1" is an integer, "1.5" is a float, "true" is a boolean, and a URL wins
    /// over generic string. Anything unparseable or empty is "string"/"unknown".
    public static func inferType(_ value: String?) -> VariableType {
        guard let value else { return .unknown }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .unknown }
        if matches(integerRe, trimmed) { return .integer }
        if matches(floatRe, trimmed) { return .float }
        if matches(booleanRe, trimmed) { return .boolean }
        if matches(urlRe, trimmed) { return .url }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let parsed = try? JsonParser.parse(trimmed), isValidJsonShape(parsed) {
                return .json
            }
        }
        return .string
    }

    private static func isValidJsonShape(_ value: JSONValue) -> Bool {
        // JsonParser is strict; reaching here means it parsed.
        true
    }
}
