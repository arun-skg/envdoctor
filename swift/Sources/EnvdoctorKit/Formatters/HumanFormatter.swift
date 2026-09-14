import Foundation

/// Render a horizontal rule the width of the given string.
public func rule(_ width: Int) -> String {
    String(repeating: "─", count: max(width, 0))
}

/// Render a single location as `relative/path:line`.
public func renderLocation(_ rootDir: String, _ origin: Origin) -> String {
    let path = displayPath(rootDir, origin.filePath)
    if let line = origin.line {
        return "\(path):\(line)"
    }
    return path
}

/// Render a full audit report matching the TypeScript reference
/// `renderReport` (src/utils/logger.ts). Colors are intentionally omitted:
/// the reference uses chalk, which emits no escape codes when stdout is not a
/// TTY, so the plain text produced here is byte-identical to the reference in
/// piped/CI contexts.
public enum HumanFormatter {
    public static func renderReport(_ audit: AuditResult, rootDir: String, verbose: Bool) -> String {
        var lines: [String] = []
        let title = "ENVIRONMENT AUDIT"
        lines.append(title)
        lines.append(rule(title.count * 2))
        lines.append("")

        if audit.findings.isEmpty {
            lines.append("  ✓ No issues found")
            lines.append("")
            lines.append(footer(audit.summary))
            return lines.joined(separator: "\n")
        }

        for spec in sectionSpecs {
            let group = audit.findings.filter { spec.ruleIds.contains($0.ruleId) }
            if group.isEmpty { continue }
            lines.append(spec.heading)
            lines.append("")
            for finding in group {
                lines.append(contentsOf: spec.render(finding, rootDir, verbose))
            }
            lines.append("")
        }

        lines.append(footer(audit.summary))
        return lines.joined(separator: "\n")
    }

    private struct SectionSpec {
        var heading: String
        var ruleIds: [String]
        var render: (Finding, String, Bool) -> [String]
    }

    private static func locationLines(_ finding: Finding, _ rootDir: String, _ verbose: Bool) -> [String] {
        guard verbose, !finding.locations.isEmpty else { return [] }
        return finding.locations.prefix(3).map { "  · \(renderLocation(rootDir, $0))" }
    }

    private static func joinLocations(_ locations: [Origin], _ rootDir: String) -> String {
        locations.map { renderLocation(rootDir, $0) }.joined(separator: ", ")
    }

    private static func captureAfter(_ message: String, _ label: String) -> String? {
        guard let range = message.range(of: label, options: [.caseInsensitive]) else { return nil }
        var rest = message[range.upperBound...]
        while let first = rest.first, first == " " { rest = rest.dropFirst() }
        var result = ""
        for ch in rest {
            if !ch.isASCII || !ch.isLetter { break }
            result.append(ch)
        }
        return result.isEmpty ? nil : result
    }

    private static let sectionSpecs: [SectionSpec] = [
        SectionSpec(heading: "Missing", ruleIds: ["missing", "undefined-in-source"]) { f, root, verbose in
            let whereText = f.locations.isEmpty
                ? "referenced but never defined"
                : "referenced in \(joinLocations(f.locations, root))"
            var lines = ["  \(f.variable)  \(whereText)"]
            lines.append(contentsOf: locationLines(f, root, verbose))
            return lines
        },
        SectionSpec(heading: "Defined but unused", ruleIds: ["unused"]) { f, root, _ in
            let whereText = f.locations.isEmpty ? "" : "defined in \(joinLocations(f.locations, root))"
            return ["  \(f.variable)  \(whereText)"]
        },
        SectionSpec(heading: "Duplicates", ruleIds: ["duplicates"]) { f, _, _ in
            ["  \(f.variable)  \(f.message)"]
        },
        SectionSpec(heading: "Type mismatch", ruleIds: ["type-mismatch"]) { f, _, _ in
            var lines = ["  \(f.variable)"]
            if let expected = captureAfter(f.message, "expected:") {
                lines.append("    expected: \(expected)")
            }
            if let found = captureAfter(f.message, "found:") {
                lines.append("    found: \(found)")
            }
            return lines
        },
        SectionSpec(heading: "Environment differences", ruleIds: ["environment-diff"]) { f, _, _ in
            ["  \(f.message)"]
        },
        SectionSpec(heading: "Public secret leak", ruleIds: ["public-prefix"]) { f, root, verbose in
            var lines = ["  \(f.variable)"]
            lines.append(contentsOf: locationLines(f, root, verbose))
            return lines
        },
        SectionSpec(heading: "Weak secrets", ruleIds: ["weak-secret"]) { f, _, _ in
            ["  \(f.variable)  \(f.message)"]
        },
        SectionSpec(heading: "Possible typos", ruleIds: ["typo"]) { f, root, verbose in
            var lines = ["  \(f.variable)  \(f.message)"]
            lines.append(contentsOf: locationLines(f, root, verbose))
            return lines
        },
        SectionSpec(heading: "Schema validation", ruleIds: ["schema-validation"]) { f, root, verbose in
            var lines = ["  \(f.variable)  \(f.message)"]
            lines.append(contentsOf: locationLines(f, root, verbose))
            return lines
        },
    ]

    private static func footer(_ summary: AuditSummary) -> String {
        let errors = summary.errors > 0 ? "\(summary.errors) error\(plural(summary.errors))" : "0 errors"
        let warnings = summary.warnings > 0 ? "\(summary.warnings) warning\(plural(summary.warnings))" : "0 warnings"
        return "Summary: \(summary.filesScanned) files scanned · \(summary.variablesFound) variables · \(errors) · \(warnings)"
    }

    private static func plural(_ n: Int) -> String {
        n == 1 ? "" : "s"
    }
}
