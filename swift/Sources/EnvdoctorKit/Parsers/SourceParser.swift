import Foundation

/// Scans source files for `process.env.NAME`, `process.env['NAME']`, and
/// `import.meta.env.NAME` usages. Comments and string literals are stripped
/// first (a state machine that understands quotes, escapes, template literals,
/// and `${...}` interpolation) so documented/string occurrences don't create
/// false positives.
public struct SourceParser: Parser {
    public let id = "source"

    private let extSet: Set<String>

    public init(extensions: [String]) {
        self.extSet = Set(extensions.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }.map { $0.lowercased() })
    }

    public func match(_ filePath: String) -> Bool {
        let ext = ((filePath as NSString).pathExtension).lowercased()
        return extSet.contains(ext)
    }

    private static let usagePatterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"\bprocess\.env\.([A-Za-z_$][\w$]*)"#), "process.env.NAME"),
        (try! NSRegularExpression(pattern: #"\bprocess\.env\[['"]([A-Za-z_$][\w$]*)['"]\]"#), "process.env['NAME']"),
        (try! NSRegularExpression(pattern: #"\bimport\.meta\.env\.([A-Za-z_$][\w$]*)"#), "import.meta.env.NAME"),
    ]

    public func parse(_ content: String, _ filePath: String) -> EnvironmentFile {
        let stripped = stripComments(content)
        var usages: [EnvironmentVariable] = []

        for (re, _) in SourceParser.usagePatterns {
            let nsRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            re.enumerateMatches(in: stripped, range: nsRange) { match, _, _ in
                guard let match,
                      let nameRange = Range(match.range(at: 1), in: stripped) else { return }
                let name = String(stripped[nameRange])
                let offset = stripped.distance(from: stripped.startIndex, to: Range(match.range, in: stripped)!.lowerBound)
                let origin = Origin(filePath: filePath, line: lineNumberAt(stripped, offset), kind: .usage, format: .source)
                usages.append(createVariable(name, nil, [origin]))
            }
        }

        return EnvironmentFile(filePath: filePath, format: .source, variables: [], usages: mergeVariables(usages))
    }
}

/// 1-based line number for a character offset in `text`.
public func lineNumberAt(_ text: String, _ offset: Int) -> Int {
    lineForOffset(text, offset)
}

private enum StripMode {
    case code
    case codeTpl
    case sq
    case dq
    case tq
}

private struct Frame {
    var mode: StripMode
    /// Brace depth for `${...}` interpolation inside a template literal.
    var tplDepth: Int
    /// Preserve string content verbatim (computed-property keys).
    var preserve: Bool
}

/// Replace comments and string-literal *contents* with spaces while preserving
/// line structure. Template-literal `${...}` interpolation is treated as code.
public func stripComments(_ code: String) -> String {
    var out = ""
    let chars = Array(code)
    let len = chars.count
    var i = 0
    var stack: [Frame] = [Frame(mode: .code, tplDepth: 0, preserve: false)]

    func current() -> Frame { stack[stack.count - 1] }

    func skipLineComment() {
        while i < len, chars[i] != "\n" {
            out += " "
            i += 1
        }
    }

    func skipBlockComment() {
        out += "  "
        i += 2
        while i < len {
            if chars[i] == "*", i + 1 < len, chars[i + 1] == "/" {
                out += "  "
                i += 2
                return
            }
            out += chars[i] == "\n" ? "\n" : " "
            i += 1
        }
    }

    while i < len {
        let c = chars[i]
        let next = i + 1 < len ? chars[i + 1] : nil
        var frame = current()

        switch frame.mode {
        case .code, .codeTpl:
            if c == "'" || c == "\"" || c == "`" {
                let stringMode: StripMode = c == "`" ? .tq : (c == "\"" ? .dq : .sq)
                // A string that immediately follows `[` is a computed-property
                // key — its content must be preserved.
                let preserve = c != "`" && i > 0 && chars[i - 1] == "["
                stack.append(Frame(mode: stringMode, tplDepth: 0, preserve: preserve))
                out.append(c)
                i += 1
                continue
            }
            if c == "/", next == "/" {
                skipLineComment()
                continue
            }
            if c == "/", next == "*" {
                skipBlockComment()
                continue
            }
            if frame.mode == .codeTpl {
                if c == "{" {
                    frame.tplDepth += 1
                    stack[stack.count - 1] = frame
                } else if c == "}" {
                    frame.tplDepth -= 1
                    if frame.tplDepth == 0 {
                        stack.removeLast()
                    } else {
                        stack[stack.count - 1] = frame
                    }
                }
            }
            out.append(c)
            i += 1

        case .tq:
            if c == "\\", let next {
                out.append(c)
                out.append(next)
                i += 2
                continue
            }
            if c == "`" {
                stack.removeLast()
                out.append(c)
                i += 1
                continue
            }
            if c == "$", next == "{" {
                out += "${"
                i += 2
                stack.append(Frame(mode: .codeTpl, tplDepth: 1, preserve: false))
                continue
            }
            // Template-literal content is blanked.
            out += " "
            i += 1

        case .sq, .dq:
            let quote: Character = frame.mode == .sq ? "'" : "\""
            if c == "\\", let next {
                if frame.preserve {
                    out.append(c)
                    out.append(next)
                } else {
                    out += "  "
                }
                i += 2
            } else if c == quote {
                out.append(c)
                i += 1
                stack.removeLast()
            } else if frame.preserve {
                out.append(c)
                i += 1
            } else {
                out += " "
                i += 1
            }
        }
    }

    return out
}
