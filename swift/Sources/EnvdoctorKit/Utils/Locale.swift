import Foundation

/// A comparator matching JavaScript's `String.prototype.localeCompare` for the
/// character set used in environment-variable names (`[A-Za-z0-9_]`).
///
/// The TypeScript reference sorts generated output with `localeCompare`, which
/// is a Unicode collation (punctuation < digits < letters, case-insensitive
/// with a lowercase-before-uppercase tiebreak) — not byte order.
public enum Locale {
    private static func primary(_ c: UInt8) -> Int {
        if c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") { return 1000 + Int(c) }
        if c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z") { return 2000 + Int(c) - 32 }
        if c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z") { return 2000 + Int(c) }
        return Int(c)
    }

    private static func caseWeight(_ c: UInt8) -> Int {
        (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) ? 0 : 1
    }

    /// Compare two strings the way JS `a.localeCompare(b)` does for env-var names.
    public static func localeCompare(_ a: String, _ b: String) -> Int {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        let len = min(aBytes.count, bBytes.count)
        // Level 1: primary weights across all positions.
        for i in 0..<len {
            let cmp = primary(aBytes[i]) - primary(bBytes[i])
            if cmp != 0 { return cmp < 0 ? -1 : 1 }
        }
        if aBytes.count != bBytes.count { return aBytes.count < bBytes.count ? -1 : 1 }
        // Level 2: case (only reached when primaries are all equal).
        for i in 0..<len {
            let cmp = caseWeight(aBytes[i]) - caseWeight(bBytes[i])
            if cmp != 0 { return cmp < 0 ? -1 : 1 }
        }
        return 0
    }

    public static func localeSort(_ values: inout [String]) {
        values.sort { localeCompare($0, $1) < 0 }
    }

    public static func sorted(_ values: some Sequence<String>) -> [String] {
        var copy = Array(values)
        localeSort(&copy)
        return copy
    }
}
