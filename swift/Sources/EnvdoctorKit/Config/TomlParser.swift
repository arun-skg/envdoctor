import Foundation

/// A minimal TOML parser covering the subset envdoctor configs use: string /
/// integer / float / boolean values, arrays, inline tables, `[table]`
/// sections, dotted keys, and comments. Produces nested
/// `[String: Any?]`-shaped values mirroring Tomlyn's `TomlTable` model.
public enum TomlParser {
    public struct Error: Swift.Error, CustomStringConvertible {
        public let description: String
    }

    /// Reference-typed table so nested `[section]` headers can be navigated
    /// and mutated without fighting Swift dictionary value semantics.
    private final class Table {
        var entries: [String: Any?] = [:]
    }

    public static func parse(_ content: String) throws -> [String: Any?] {
        let root = Table()
        var current = root

        let lines = content.components(separatedBy: "\n")
        for (idx, rawLine) in lines.enumerated() {
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lineNo = idx + 1

            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else {
                    throw Error(description: "line \(lineNo): malformed table header")
                }
                let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                let path = try parseKeyPath(inner, lineNo)
                var node = root
                for part in path {
                    if let existing = node.entries[part] as? Table {
                        node = existing
                    } else {
                        let table = Table()
                        node.entries[part] = table
                        node = table
                    }
                }
                current = node
                continue
            }

            guard let eq = findEqualsOutsideString(line) else {
                throw Error(description: "line \(lineNo): expected key = value")
            }
            let keyPath = try parseKeyPath(String(line[..<eq]).trimmingCharacters(in: .whitespaces), lineNo)
            let value = try parseValue(String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces), lineNo)
            try assign(&current.entries, keyPath: keyPath, value: value, lineNo: lineNo)
        }
        return plain(root)
    }

    private static func plain(_ table: Table) -> [String: Any?] {
        var out: [String: Any?] = [:]
        for (key, value) in table.entries {
            switch value {
            case let child as Table:
                out[key] = plain(child)
            case let list as [Any?]:
                out[key] = list.map { item -> Any? in
                    if let t = item as? Table { return plain(t) }
                    if let l = item as? [Any?] { return l }
                    return item
                }
            default:
                out[key] = value
            }
        }
        return out
    }

    private static func assign(_ entries: inout [String: Any?], keyPath: [String], value: Any?, lineNo: Int) throws {
        if keyPath.count == 1 {
            if entries[keyPath[0]] != nil {
                throw Error(description: "line \(lineNo): duplicate key '\(keyPath[0])'")
            }
            entries[keyPath[0]] = value
            return
        }
        let head = keyPath[0]
        if entries[head] == nil {
            entries[head] = Table()
        }
        guard let table = entries[head] as? Table else {
            throw Error(description: "line \(lineNo): key '\(head)' is not a table")
        }
        try assign(&table.entries, keyPath: Array(keyPath[1...]), value: value, lineNo: lineNo)
    }

    private static func stripComment(_ line: String) -> String {
        var inString = false
        var quoteChar: Character = " "
        var escaped = false
        var result = ""
        for ch in line {
            if inString {
                result.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" && quoteChar == "\"" {
                    escaped = true
                } else if ch == quoteChar {
                    inString = false
                }
            } else if ch == "\"" || ch == "'" {
                inString = true
                quoteChar = ch
                result.append(ch)
            } else if ch == "#" {
                break
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private static func findEqualsOutsideString(_ line: String) -> String.Index? {
        var inString = false
        var quoteChar: Character = " "
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if inString {
                if ch == quoteChar { inString = false }
            } else if ch == "\"" || ch == "'" {
                inString = true
                quoteChar = ch
            } else if ch == "=" {
                let prev = index > line.startIndex ? line[line.index(before: index)] : " "
                let next = line.index(after: index)
                let prevIsOp = prev == "=" || prev == "<" || prev == ">" || prev == "!"
                let nextIsEq = next < line.endIndex && line[next] == "="
                if !prevIsOp && !nextIsEq {
                    return index
                }
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func parseKeyPath(_ text: String, _ lineNo: Int) throws -> [String] {
        try text.split(separator: ".").map { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
                guard trimmed.count >= 2 else { throw Error(description: "line \(lineNo): bad quoted key") }
                return String(trimmed.dropFirst().dropLast())
            }
            guard !trimmed.isEmpty else { throw Error(description: "line \(lineNo): empty key") }
            return trimmed
        }
    }

    private static func parseValue(_ text: String, _ lineNo: Int) throws -> Any? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { throw Error(description: "line \(lineNo): missing value") }
        if value.hasPrefix("\"") {
            return try parseBasicString(value, lineNo)
        }
        if value.hasPrefix("'") {
            guard value.hasSuffix("'"), value.count >= 2 else {
                throw Error(description: "line \(lineNo): unterminated literal string")
            }
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("[") {
            return try parseArray(value, lineNo)
        }
        if value.hasPrefix("{") {
            return try parseInlineTable(value, lineNo)
        }
        switch value {
        case "true": return true
        case "false": return false
        default: break
        }
        // TOML requires underscores may separate digits; normalize them.
        let numeric = value.replacingOccurrences(of: "_", with: "")
        if let i = Int(numeric) { return i }
        if let d = Double(numeric) { return d }
        // Datetimes and bare tokens are outside the config subset.
        throw Error(description: "line \(lineNo): invalid value '\(value)'")
    }

    private static func parseBasicString(_ value: String, _ lineNo: Int) throws -> String {
        var result = ""
        var i = value.index(after: value.startIndex)
        while i < value.endIndex {
            let ch = value[i]
            if ch == "\"" {
                return result
            }
            if ch == "\\" {
                let next = value.index(after: i)
                guard next < value.endIndex else { break }
                let esc = value[next]
                switch esc {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "u":
                    let hexStart = value.index(after: next)
                    let hexEnd = value.index(hexStart, offsetBy: 4, limitedBy: value.endIndex) ?? value.endIndex
                    guard let code = UInt32(String(value[hexStart..<hexEnd]), radix: 16),
                          let scalar = Unicode.Scalar(code) else {
                        throw Error(description: "line \(lineNo): bad \\u escape")
                    }
                    result.unicodeScalars.append(scalar)
                    i = hexEnd
                    continue
                default:
                    throw Error(description: "line \(lineNo): bad escape '\\\(esc)'")
                }
                i = value.index(after: next)
                continue
            }
            result.append(ch)
            i = value.index(after: i)
        }
        throw Error(description: "line \(lineNo): unterminated string")
    }

    private static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var inString = false
        var quoteChar: Character = " "
        var current = ""
        for ch in text {
            if inString {
                current.append(ch)
                if ch == quoteChar { inString = false }
                continue
            }
            if ch == "\"" || ch == "'" {
                inString = true
                quoteChar = ch
                current.append(ch)
            } else if ch == "[" || ch == "{" {
                depth += 1
                current.append(ch)
            } else if ch == "]" || ch == "}" {
                depth -= 1
                current.append(ch)
            } else if ch == "," && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current)
        }
        return parts
    }

    private static func parseArray(_ value: String, _ lineNo: Int) throws -> [Any?] {
        guard value.hasSuffix("]") else {
            throw Error(description: "line \(lineNo): unterminated array")
        }
        let inner = String(value.dropFirst().dropLast())
        return try splitTopLevel(inner).map { try parseValue($0, lineNo) }
    }

    private static func parseInlineTable(_ value: String, _ lineNo: Int) throws -> [String: Any?] {
        guard value.hasSuffix("}") else {
            throw Error(description: "line \(lineNo): unterminated inline table")
        }
        let inner = String(value.dropFirst().dropLast())
        let table = Table()
        for part in splitTopLevel(inner) {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = findEqualsOutsideString(trimmed) else {
                throw Error(description: "line \(lineNo): expected key = value in inline table")
            }
            let keyPath = try parseKeyPath(String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces), lineNo)
            let raw = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            try assign(&table.entries, keyPath: keyPath, value: try parseValue(raw, lineNo), lineNo: lineNo)
        }
        return table.entries
    }
}
