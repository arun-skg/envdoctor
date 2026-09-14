import Foundation

/// Glob matching for variable names and file names (`*` within a segment,
/// `**` across segments, `?` for one character).
public enum Glob {
    public static func globToRegExp(_ pattern: String) -> NSRegularExpression? {
        var re = ""
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "*" {
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    re += ".*"
                    i += 2
                } else {
                    re += "[^/]*"
                    i += 1
                }
            } else if c == "?" {
                re += "[^/]"
                i += 1
            } else {
                re += NSRegularExpression.escapedPattern(for: String(c))
                i += 1
            }
        }
        return try? NSRegularExpression(pattern: "^\(re)$")
    }

    public static func matchesGlob(_ pattern: String, _ value: String) -> Bool {
        guard let re = globToRegExp(pattern) else { return false }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return re.firstMatch(in: value, range: range) != nil
    }

    public static func matchesAnyGlob(_ patterns: some Sequence<String>, _ value: String) -> Bool {
        patterns.contains { matchesGlob($0, value) }
    }
}

/// Translate a path glob (with `**`, `*`, `?`, and `{a,b}` braces) to a regex
/// matched against a root-relative, forward-slash path — mirroring
/// fast-glob's pattern semantics used by the reference discovery.
public enum PathGlob {
    public static func toRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: convert(pattern))
    }

    public static func matches(_ pattern: String, _ path: String) -> Bool {
        guard let re = toRegex(pattern) else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return re.firstMatch(in: path, range: range) != nil
    }

    private static func convert(_ pattern: String) -> String {
        let chars = Array(pattern)
        var sb = "^"
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    // `**/`: zero or more whole segments; bare `**`: anything.
                    if i + 2 < chars.count && chars[i + 2] == "/" {
                        sb += "(?:.*/)?"
                        i += 3
                    } else {
                        sb += ".*"
                        i += 2
                    }
                } else {
                    sb += "[^/]*"
                    i += 1
                }
            case "?":
                sb += "[^/]"
                i += 1
            case "{":
                guard let close = findBraceEnd(chars, start: i) else {
                    sb += "\\{"
                    i += 1
                    continue
                }
                let inner = String(chars[(i + 1)..<close])
                let options = inner.split(separator: ",").map { NSRegularExpression.escapedPattern(for: String($0)) }
                sb += "(?:" + options.joined(separator: "|") + ")"
                i = close + 1
            default:
                sb += NSRegularExpression.escapedPattern(for: String(c))
                i += 1
            }
        }
        sb += "$"
        return sb
    }

    private static func findBraceEnd(_ chars: [Character], start: Int) -> Int? {
        var i = start + 1
        while i < chars.count {
            if chars[i] == "}" { return i }
            i += 1
        }
        return nil
    }
}
