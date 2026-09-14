import Foundation

/// Parser for dotenv-style files (`.env`, `.env.local`, `.env.production`, ...).
///
/// Hand-rolled tokenizer (mirroring the TypeScript reference) because the audit
/// needs every occurrence of a key — to detect duplicates and attribute origins
/// with line numbers.
public struct EnvParser: Parser {
    public let id = "dotenv"

    public init() {}

    public func match(_ filePath: String) -> Bool {
        let base = (filePath as NSString).lastPathComponent
        guard let re = try? NSRegularExpression(pattern: #"^\.env(\..+)?$"#) else { return false }
        let range = NSRange(base.startIndex..<base.endIndex, in: base)
        return re.firstMatch(in: base, range: range) != nil
    }

    public func parse(_ content: String, _ filePath: String) -> EnvironmentFile {
        let environment = environmentLabelForDotenv(filePath)
        var entries = parseDotenv(content)
        applyIgnoreDirectives(&entries, parseIgnoreDirectives(content))
        let variables = entries.map { entry in
            createVariable(
                entry.key,
                entry.value,
                [Origin(filePath: filePath, line: entry.line, kind: .definition, environment: environment, format: .dotenv)],
                entry.ignoreRules
            )
        }
        return EnvironmentFile(filePath: filePath, format: .dotenv, environment: environment, variables: variables, usages: [])
    }
}

/// The environment label derived from a dotenv filename.
public func environmentLabelForDotenv(_ filePath: String) -> String {
    let base = (filePath as NSString).lastPathComponent
    if base == ".env" { return "development" }
    if base == ".env.example" { return "example" }
    var suffix = base
    if suffix.hasPrefix(".env.") {
        suffix = String(suffix.dropFirst(5))
    } else if suffix.hasPrefix(".env") {
        suffix = String(suffix.dropFirst(4))
    }
    if suffix.isEmpty { return "development" }
    // `.env.development.local` → development, `.env.test` → test
    if suffix.hasSuffix(".local") {
        suffix = String(suffix.dropLast(6))
    }
    while suffix.hasSuffix(".") {
        suffix = String(suffix.dropLast())
    }
    return suffix.isEmpty ? "development" : suffix
}

public struct EnvEntry {
    var key: String
    var value: String?
    var line: Int
    var ignoreRules: [String]?
}

struct IgnoreDirective {
    var line: Int
    var rules: [String]
}

private func isKeyChar(_ ch: Character) -> Bool {
    // /[\w.-]/ — word chars (ASCII letters, digits, _), dot, dash
    if ch == "_" || ch == "." || ch == "-" { return true }
    if ch >= "a" && ch <= "z" { return true }
    if ch >= "A" && ch <= "Z" { return true }
    if ch >= "0" && ch <= "9" { return true }
    // \w with Unicode flag matches non-ASCII letters too; support them.
    return ch.isLetter || ch.isNumber
}

/// Parse dotenv content into key/value/line entries.
public func parseDotenv(_ content: String) -> [EnvEntry] {
    var entries: [EnvEntry] = []
    let chars = Array(content)
    let len = chars.count
    var i = 0
    var line = 1

    func isWhitespace(_ ch: Character) -> Bool {
        ch == " " || ch == "\t" || ch == "\r" || ch == "\n" || ch == "\u{0B}" || ch == "\u{0C}"
    }

    while i < len {
        // Skip whitespace and blank lines.
        while i < len, isWhitespace(chars[i]) {
            if chars[i] == "\n" { line += 1 }
            i += 1
        }
        if i >= len { break }

        // Full-line comment.
        if chars[i] == "#" {
            while i < len, chars[i] != "\n" { i += 1 }
            continue
        }

        // Optional `export` prefix, allowing spaces and tabs between the prefix
        // and the variable name (mirrors /export[ \t]+/).
        if i + 6 <= len {
            let slice = chars[i..<min(len, i + 6)]
            if slice.starts(with: ["e", "x", "p", "o", "r", "t"]) {
                let after = i + 6
                if after < len, chars[after] == " " || chars[after] == "\t" {
                    i = after
                    while i < len, (chars[i] == " " || chars[i] == "\t") { i += 1 }
                }
            }
        }

        let startLine = line

        // Read the key.
        let keyStart = i
        while i < len, isKeyChar(chars[i]) { i += 1 }
        if i == keyStart {
            while i < len, chars[i] != "\n" { i += 1 }
            continue
        }
        let key = String(chars[keyStart..<i])

        // Skip whitespace before `=`.
        while i < len, chars[i] != "=", chars[i] != "\n", isWhitespace(chars[i]) { i += 1 }
        if i >= len || chars[i] != "=" {
            // Malformed line (no `=`); ignore it like dotenv does.
            while i < len, chars[i] != "\n" { i += 1 }
            continue
        }
        i += 1 // consume `=`

        // Skip whitespace before the value.
        while i < len, chars[i] != "\n", isWhitespace(chars[i]) { i += 1 }

        let value: String
        if i < len, (chars[i] == "\"" || chars[i] == "'" || chars[i] == "`") {
            let quote = chars[i]
            i += 1
            var raw = ""
            while i < len {
                let c = chars[i]
                if c == quote {
                    i += 1
                    break
                }
                if c == "\\" {
                    let nextIndex = i + 1
                    if nextIndex < len {
                        let next = chars[nextIndex]
                        if quote == "\"" && next == "n" {
                            raw += "\n"
                            i += 2
                            continue
                        }
                        if quote == "\"" && next == "t" {
                            raw += "\t"
                            i += 2
                            continue
                        }
                        if quote == "\"" && next == "r" {
                            raw += "\r"
                            i += 2
                            continue
                        }
                        if next == "\"" || next == "'" || next == "`" || next == "\\" {
                            raw.append(next)
                            i += 2
                            continue
                        }
                    }
                    raw.append(c)
                    i += 1
                    continue
                }
                raw.append(c)
                if c == "\n" { line += 1 }
                i += 1
            }
            value = raw
        } else {
            // Unquoted value: ends at newline or an unescaped `#`.
            var raw = ""
            while i < len, chars[i] != "\n" {
                let c = chars[i]
                if c == "\\", i + 1 < len, chars[i + 1] == "#" {
                    raw += "#"
                    i += 2
                    continue
                }
                if c == "#" { break }
                raw.append(c)
                i += 1
            }
            value = trimEnd(raw)
        }

        entries.append(EnvEntry(key: key, value: value, line: startLine))
    }

    return entries
}

private func trimEnd(_ s: String) -> String {
    var scalars = Array(s.unicodeScalars)
    while let last = scalars.last {
        if last == " " || last == "\t" || last == "\r" || last == "\n" || last == "\u{0B}" || last == "\u{0C}" {
            scalars.removeLast()
        } else {
            break
        }
    }
    return String(decoding: scalars.map(\.value), as: UTF32.self)
}

private func parseIgnoreDirectives(_ content: String) -> [IgnoreDirective] {
    var directives: [IgnoreDirective] = []
    let lines = content.components(separatedBy: "\n")
    guard let re = try? NSRegularExpression(pattern: #"^#\s*envdoctor:ignore\s+([a-z0-9_,\-\s]+)\s*$"#, options: [.caseInsensitive]) else {
        return directives
    }
    for (i, text) in lines.enumerated() {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { continue }
        guard let rulesRange = Range(match.range(at: 1), in: text) else { continue }
        let rules = String(text[rulesRange])
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !rules.isEmpty {
            directives.append(IgnoreDirective(line: i + 1, rules: rules))
        }
    }
    return directives
}

private func applyIgnoreDirectives(_ entries: inout [EnvEntry], _ directives: [IgnoreDirective]) {
    var entryByLine: [Int: Int] = [:] // line -> index in entries
    for (idx, entry) in entries.enumerated() {
        entryByLine[entry.line] = idx
    }
    var pending: [String] = []
    let maxEntryLine = entries.map(\.line).max() ?? 1
    let maxDirectiveLine = directives.map(\.line).max() ?? 1
    let lines = max(1, max(maxEntryLine, maxDirectiveLine))
    for line in 1...lines {
        if let directive = directives.first(where: { $0.line == line }) {
            pending.append(contentsOf: directive.rules)
        }
        if let idx = entryByLine[line], !pending.isEmpty {
            entries[idx].ignoreRules = (entries[idx].ignoreRules ?? []) + pending
            pending = []
        }
    }
}
