import Foundation

public struct Interpolation {
    public var name: String
    public var line: Int
}

/// Compute the 1-based line number of a character offset in `content`.
public func lineForOffset(_ content: String, _ offset: Int) -> Int {
    var line = 1
    let chars = Array(content)
    let end = min(offset, chars.count)
    for i in 0..<end where chars[i] == "\n" {
        line += 1
    }
    return line
}

/// Scan `content` for `$VAR` and `${VAR}` interpolations, honoring the `$$`
/// escape. `{...}` modifiers (`${VAR:-x}` etc.) are stripped — only the name
/// is kept.
public func scanInterpolations(_ content: String) -> [Interpolation] {
    // Protect escaped `$$` (same length, so offsets stay valid).
    var chars = Array(content)
    var i = 0
    while i + 1 < chars.count {
        if chars[i] == "$" && chars[i + 1] == "$" {
            chars[i] = " "
            chars[i + 1] = " "
            i += 2
        } else {
            i += 1
        }
    }
    let protectedContent = String(chars)

    var results: [Interpolation] = []
    let pattern = #"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)(?:\s*[:-?+][^}]*)?\}|([A-Za-z_][A-Za-z0-9_]*))"#
    guard let re = try? NSRegularExpression(pattern: pattern) else { return results }
    let nsRange = NSRange(protectedContent.startIndex..<protectedContent.endIndex, in: protectedContent)
    re.enumerateMatches(in: protectedContent, range: nsRange) { match, _, _ in
        guard let match, let matchRange = Range(match.range, in: protectedContent) else { return }
        let name: String
        if match.range(at: 1).location != NSNotFound, let r = Range(match.range(at: 1), in: protectedContent) {
            name = String(protectedContent[r])
        } else if match.range(at: 2).location != NSNotFound, let r = Range(match.range(at: 2), in: protectedContent) {
            name = String(protectedContent[r])
        } else {
            return
        }
        results.append(Interpolation(name: name, line: lineForOffset(content, protectedContent.distance(from: protectedContent.startIndex, to: matchRange.lowerBound))))
    }
    return results
}

/// Best-effort line lookup for a definition name in the raw YAML text,
/// supporting both map form (`KEY: value`) and list form (`- KEY=value`).
public func lineForNameMapOrList(_ content: String, _ name: String) -> Int? {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    let pattern = #"^\s*[- ]*["']?"# + escaped + #"["']?\s*[:=]"#
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
    let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
    guard let match = re.firstMatch(in: content, range: nsRange),
          let range = Range(match.range, in: content) else { return nil }
    return lineForOffset(content, content.distance(from: content.startIndex, to: range.lowerBound))
}

/// Best-effort line lookup for an `env:` key in the raw YAML text (map form).
public func lineForNameMap(_ content: String, _ name: String) -> Int? {
    let escaped = NSRegularExpression.escapedPattern(for: name)
    let pattern = #"^\s*["']?"# + escaped + #"["']?\s*:"#
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
    let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
    guard let match = re.firstMatch(in: content, range: nsRange),
          let range = Range(match.range, in: content) else { return nil }
    return lineForOffset(content, content.distance(from: content.startIndex, to: range.lowerBound))
}
