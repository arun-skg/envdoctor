import Foundation

/// Render a complete `AuditResult` as the reference CLI's JSON shape
/// (`scan --format json`): camelCase keys, `exitCode` → `summary` → `findings`.
public enum ScanJsonFormatter {
    public static func render(_ audit: AuditResult, rootDir: String) -> String {
        Json.pretty(toJson(audit, rootDir))
    }

    public static func toJson(_ audit: AuditResult, _ rootDir: String) -> JSONValue {
        var summary = JSONObject()
        summary.set("filesScanned", .int(audit.summary.filesScanned))
        summary.set("variablesFound", .int(audit.summary.variablesFound))
        summary.set("errors", .int(audit.summary.errors))
        summary.set("warnings", .int(audit.summary.warnings))
        summary.set("infos", .int(audit.summary.infos))
        summary.set("total", .int(audit.summary.total))

        let findings: [JSONValue] = audit.findings.map { f in
            var finding = JSONObject()
            finding.set("id", .string(f.id))
            finding.set("ruleId", .string(f.ruleId))
            finding.set("severity", .string(f.severity.rawValue))
            finding.set("variable", .string(f.variable))
            finding.set("message", .string(f.message))
            let locations: [JSONValue] = f.locations.map { o in
                var loc = JSONObject()
                loc.set("file", .string(displayPath(rootDir, o.filePath)))
                if let line = o.line {
                    loc.set("line", .int(line))
                }
                loc.set("kind", .string(o.kind.rawValue))
                return .object(loc)
            }
            finding.set("locations", .array(locations))
            return .object(finding)
        }

        var root = JSONObject()
        root.set("exitCode", .int(audit.exitCode))
        root.set("summary", .object(summary))
        root.set("findings", .array(findings))
        return .object(root)
    }
}

/// Serialize an origin for JSON output (values never appear).
public func originToJson(_ rootDir: String, _ origin: Origin) -> JSONValue {
    var loc = JSONObject()
    loc.set("file", .string(displayPath(rootDir, origin.filePath)))
    if let line = origin.line {
        loc.set("line", .int(line))
    }
    loc.set("kind", .string(origin.kind.rawValue))
    return .object(loc)
}
