import Foundation

/// A JSON value with insertion-ordered object keys.
public indirect enum JSONValue {
    case null
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
    case array([JSONValue])
    case object(JSONObject)
}

/// An insertion-ordered JSON object.
public struct JSONObject {
    public var entries: [(String, JSONValue)] = []

    public init() {}

    public subscript(key: String) -> JSONValue? {
        for (k, v) in entries where k == key { return v }
        return nil
    }

    public mutating func set(_ key: String, _ value: JSONValue) {
        entries.append((key, value))
    }

    public func appending(_ key: String, _ value: JSONValue) -> JSONObject {
        var copy = self
        copy.set(key, value)
        return copy
    }
}

/// A minimal JSON writer producing the exact byte shape of
/// `JSON.stringify(x, null, 2)`: two-space indentation, `": "` key separator,
/// `{}`/`[]` for empty containers, and control-character escaping with
/// lowercase hex.
public enum Json {
    public static func pretty(_ value: JSONValue) -> String {
        var sb = ""
        write(&sb, value, 0, pretty: true)
        return sb
    }

    public static func compact(_ value: JSONValue) -> String {
        var sb = ""
        write(&sb, value, 0, pretty: false)
        return sb
    }

    private static func write(_ sb: inout String, _ value: JSONValue, _ depth: Int, pretty: Bool) {
        switch value {
        case .null: sb += "null"
        case .bool(let b): sb += b ? "true" : "false"
        case .string(let s): writeString(&sb, s)
        case .int(let i): sb += String(i)
        case .double(let d): sb += jsNumber(d)
        case .array(let items): writeArray(&sb, items, depth, pretty: pretty)
        case .object(let obj): writeObject(&sb, obj.entries, depth, pretty: pretty)
        }
    }

    private static func writeObject(_ sb: inout String, _ entries: [(String, JSONValue)], _ depth: Int, pretty: Bool) {
        if entries.isEmpty {
            sb += "{}"
            return
        }
        sb += "{"
        for (i, entry) in entries.enumerated() {
            if pretty {
                sb += "\n"
                indent(&sb, depth + 1)
            }
            writeString(&sb, entry.0)
            sb += pretty ? ": " : ":"
            write(&sb, entry.1, depth + 1, pretty: pretty)
            if i < entries.count - 1 { sb += "," }
        }
        if pretty {
            sb += "\n"
            indent(&sb, depth)
        }
        sb += "}"
    }

    private static func writeArray(_ sb: inout String, _ items: [JSONValue], _ depth: Int, pretty: Bool) {
        if items.isEmpty {
            sb += "[]"
            return
        }
        sb += "["
        for (i, item) in items.enumerated() {
            if pretty {
                sb += "\n"
                indent(&sb, depth + 1)
            }
            write(&sb, item, depth + 1, pretty: pretty)
            if i < items.count - 1 { sb += "," }
        }
        if pretty {
            sb += "\n"
            indent(&sb, depth)
        }
        sb += "]"
    }

    private static func indent(_ sb: inout String, _ depth: Int) {
        for _ in 0..<depth { sb += "  " }
    }

    private static func writeString(_ sb: inout String, _ s: String) {
        sb += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": sb += "\\\""
            case "\\": sb += "\\\\"
            case "\u{08}": sb += "\\b"
            case "\u{0C}": sb += "\\f"
            case "\n": sb += "\\n"
            case "\r": sb += "\\r"
            case "\t": sb += "\\t"
            default:
                if scalar.value < 0x20 {
                    sb += String(format: "\\u%04x", scalar.value)
                } else {
                    sb.unicodeScalars.append(scalar)
                }
            }
        }
        sb += "\""
    }

    /// JS number-to-string: shortest round-trip, lowercase `e` exponent
    /// without leading zeros, matching `Number.prototype.toString`.
    static func jsNumber(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e21 {
            return String(Int64(d))
        }
        var s = String(d)
        // Swift prints e.g. "1.5e-07"; JS prints "1.5e-7".
        if let eRange = s.range(of: "e") {
            let mantissa = s[s.startIndex..<eRange.lowerBound]
            var exp = String(s[eRange.upperBound...])
            var neg = false
            if exp.hasPrefix("-") { neg = true; exp.removeFirst() }
            else if exp.hasPrefix("+") { exp.removeFirst() }
            exp = exp.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
            if exp.isEmpty { exp = "0" }
            s = "\(mantissa)e\(neg ? "-" : "+")\(exp)"
        }
        return s
    }
}

/// Parsing of JSON text into `JSONValue` (used for config files, baselines,
/// and snapshot JSON). Mirrors `JSON.parse` semantics closely enough for
/// envdoctor's own artifacts.
public enum JsonParser {
    public struct Error: Swift.Error, CustomStringConvertible {
        public let description: String
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var scalars = Array(text.unicodeScalars)
        var pos = 0
        let value = try parseValue(&scalars, &pos)
        skipWhitespace(&scalars, &pos)
        guard pos >= scalars.count else {
            throw Error(description: "Unexpected trailing characters in JSON")
        }
        return value
    }

    private static func skipWhitespace(_ s: inout [Unicode.Scalar], _ pos: inout Int) {
        while pos < s.count {
            let c = s[pos]
            if c == " " || c == "\t" || c == "\n" || c == "\r" { pos += 1 } else { break }
        }
    }

    private static func parseValue(_ s: inout [Unicode.Scalar], _ pos: inout Int) throws -> JSONValue {
        skipWhitespace(&s, &pos)
        guard pos < s.count else { throw Error(description: "Unexpected end of JSON") }
        switch s[pos] {
        case "{": return try parseObject(&s, &pos)
        case "[": return try parseArray(&s, &pos)
        case "\"": return .string(try parseString(&s, &pos))
        case "t":
            try expect(&s, &pos, "true"); return .bool(true)
        case "f":
            try expect(&s, &pos, "false"); return .bool(false)
        case "n":
            try expect(&s, &pos, "null"); return .null
        default:
            return try parseNumber(&s, &pos)
        }
    }

    private static func expect(_ s: inout [Unicode.Scalar], _ pos: inout Int, _ word: String) throws {
        for ch in word.unicodeScalars {
            guard pos < s.count, s[pos] == ch else {
                throw Error(description: "Invalid JSON literal")
            }
            pos += 1
        }
    }

    private static func parseObject(_ s: inout [Unicode.Scalar], _ pos: inout Int) throws -> JSONValue {
        pos += 1 // consume '{'
        var obj = JSONObject()
        skipWhitespace(&s, &pos)
        if pos < s.count && s[pos] == "}" { pos += 1; return .object(obj) }
        while true {
            skipWhitespace(&s, &pos)
            guard pos < s.count, s[pos] == "\"" else { throw Error(description: "Expected string key") }
            let key = try parseString(&s, &pos)
            skipWhitespace(&s, &pos)
            guard pos < s.count, s[pos] == ":" else { throw Error(description: "Expected ':'") }
            pos += 1
            let value = try parseValue(&s, &pos)
            obj.set(key, value)
            skipWhitespace(&s, &pos)
            guard pos < s.count else { throw Error(description: "Unterminated object") }
            if s[pos] == "," { pos += 1; continue }
            if s[pos] == "}" { pos += 1; return .object(obj) }
            throw Error(description: "Expected ',' or '}'")
        }
    }

    private static func parseArray(_ s: inout [Unicode.Scalar], _ pos: inout Int) throws -> JSONValue {
        pos += 1 // consume '['
        var items: [JSONValue] = []
        skipWhitespace(&s, &pos)
        if pos < s.count && s[pos] == "]" { pos += 1; return .array(items) }
        while true {
            let value = try parseValue(&s, &pos)
            items.append(value)
            skipWhitespace(&s, &pos)
            guard pos < s.count else { throw Error(description: "Unterminated array") }
            if s[pos] == "," { pos += 1; continue }
            if s[pos] == "]" { pos += 1; return .array(items) }
            throw Error(description: "Expected ',' or ']'")
        }
    }

    private static func parseString(_ s: inout [Unicode.Scalar], _ pos: inout Int) throws -> String {
        pos += 1 // consume '"'
        var result = String.UnicodeScalarView()
        while pos < s.count {
            let c = s[pos]
            if c == "\"" {
                pos += 1
                return String(result)
            }
            if c == "\\" {
                pos += 1
                guard pos < s.count else { break }
                let esc = s[pos]
                switch esc {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    guard pos + 4 < s.count else { throw Error(description: "Bad \\u escape") }
                    let hex = String(String.UnicodeScalarView(s[(pos + 1)...(pos + 4)]))
                    guard let code = UInt32(hex, radix: 16) else { throw Error(description: "Bad \\u escape") }
                    if let scalar = Unicode.Scalar(code) {
                        result.append(scalar)
                    }
                    pos += 4
                default:
                    throw Error(description: "Bad escape")
                }
                pos += 1
                continue
            }
            result.append(c)
            pos += 1
        }
        throw Error(description: "Unterminated string")
    }

    private static func parseNumber(_ s: inout [Unicode.Scalar], _ pos: inout Int) throws -> JSONValue {
        let start = pos
        if pos < s.count && (s[pos] == "-" || s[pos] == "+") { pos += 1 }
        var isDouble = false
        while pos < s.count {
            let c = s[pos]
            if c >= "0" && c <= "9" {
                pos += 1
            } else if c == "." || c == "e" || c == "E" || c == "-" || c == "+" {
                isDouble = true
                pos += 1
            } else {
                break
            }
        }
        let text = String(String.UnicodeScalarView(s[start..<pos]))
        if text.isEmpty { throw Error(description: "Invalid JSON value") }
        if isDouble {
            guard let d = Double(text) else { throw Error(description: "Invalid number") }
            return .double(d)
        }
        guard let i = Int(text) else {
            guard let d = Double(text) else { throw Error(description: "Invalid number") }
            return .double(d)
        }
        return .int(i)
    }
}

public extension JSONValue {
    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var asObject: JSONObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    var asArray: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        asObject?.entries.first { $0.0 == key }?.1
    }
}
