import Foundation
import Yams

/// A YAML value with the scalar-resolution semantics of the reference's
/// `yaml` npm package (YAML 1.2 core schema), as reproduced by the other
/// ports: plain scalars become null/bool/int/float/string; quoted scalars are
/// always strings.
public enum YamlValue {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([YamlValue])
    case map(YamlMap)
}

/// An insertion-ordered YAML mapping.
public struct YamlMap {
    public var entries: [(String, YamlValue)] = []

    public init() {}

    public subscript(key: String) -> YamlValue? {
        entries.first { $0.0 == key }?.1
    }

    public func contains(_ key: String) -> Bool {
        entries.contains { $0.0 == key }
    }
}

public func jsString(_ value: YamlValue?) -> String {
    guard let value else { return "null" }
    switch value {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .int(let i): return String(i)
    case .double(let d): return Json.jsNumber(d)
    case .string(let s): return s
    case .array(let items): return items.map { jsString($0) }.joined(separator: ",")
    case .map: return "[object Object]"
    }
}

public enum YamlFacade {
    private static let intRe = try! NSRegularExpression(pattern: #"^[-+]?[0-9]+$"#)
    private static let hexIntRe = try! NSRegularExpression(pattern: #"^0x[0-9a-fA-F]+$"#)
    private static let octIntRe = try! NSRegularExpression(pattern: #"^0o[0-7]+$"#)
    private static let floatRe = try! NSRegularExpression(pattern: #"^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$"#)

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.firstMatch(in: s, range: range) != nil
    }

    /// Parse all `---`-separated documents; returns an empty list when the
    /// content is not parseable YAML (callers still scan raw text for
    /// interpolations).
    public static func loadAll(_ content: String) -> [YamlValue] {
        // Split on document separator lines, then compose each document.
        var docs: [YamlValue] = []
        var current = ""
        var hasCurrent = false
        func flush() {
            guard hasCurrent else { return }
            if let value = loadFirst(current) {
                docs.append(value)
            }
            current = ""
            hasCurrent = false
        }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed.hasPrefix("--- ") {
                flush()
                continue
            }
            if trimmed == "..." {
                flush()
                continue
            }
            current += line + "\n"
            hasCurrent = true
        }
        flush()
        return docs
    }

    /// Parse the first document; null when unparseable or empty.
    public static func loadFirst(_ content: String) -> YamlValue? {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            guard let root = try Yams.compose(yaml: content) else { return nil }
            return toPlain(root)
        } catch {
            return nil
        }
    }

    public static func toPlain(_ node: Node) -> YamlValue {
        switch node {
        case .scalar(let scalar):
            return resolveScalar(scalar)
        case .sequence(let seq):
            return .array(seq.map(toPlain))
        case .mapping(let map):
            var out = YamlMap()
            for (key, value) in map {
                let resolvedKey = jsString(toPlain(key))
                out.entries.append((resolvedKey, toPlain(value)))
            }
            return .map(out)
        case .alias:
            // Anchors/aliases are not resolved here (the reference parser
            // resolves them); treat as absent.
            return .null
        }
    }

    private static func resolveScalar(_ scalar: Node.Scalar) -> YamlValue {
        let style = scalar.style
        let s = scalar.string
        // Quoted (or literal/folded) scalars are always strings.
        if style != .any && style != .plain {
            return .string(s)
        }
        if s.isEmpty || s == "~" || s == "null" || s == "Null" || s == "NULL" {
            return .null
        }
        if s == "true" || s == "True" || s == "TRUE" { return .bool(true) }
        if s == "false" || s == "False" || s == "FALSE" { return .bool(false) }
        if matches(intRe, s), let i = Int(s) {
            return .int(i)
        }
        if matches(hexIntRe, s), let i = UInt64(String(s.dropFirst(2)), radix: 16) {
            return .int(Int(i))
        }
        if matches(octIntRe, s), let i = UInt64(String(s.dropFirst(2)), radix: 8) {
            return .int(Int(i))
        }
        if (s.contains(".") || s.contains("e") || s.contains("E")), matches(floatRe, s), let d = Double(s) {
            return .double(d)
        }
        return .string(s)
    }
}
