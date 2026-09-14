import Foundation

private let sarifSchema = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"

/// Format an audit result as SARIF 2.1.0 JSON, byte-matching the reference
/// `formatSarif` (src/formatters/sarif.ts).
public enum SarifFormatter {
    private static func severityToLevel(_ severity: Severity) -> String {
        switch severity {
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "note"
        }
    }

    private static func defaultLevelForDetector(_ ruleId: String) -> String {
        if ["missing", "undefined-in-source", "type-mismatch", "public-prefix"].contains(ruleId) {
            return "error"
        }
        return "warning"
    }

    public static func renderSarif(_ audit: AuditResult, rootDir: String) -> String {
        Json.pretty(sarifValue(audit, rootDir))
    }

    public static func sarifValue(_ audit: AuditResult, _ rootDir: String) -> JSONValue {
        let rules: [JSONValue] = Audit.allDetectors.map { d in
            var rule = JSONObject()
            rule.set("id", .string(d.id))
            rule.set("name", .string(d.name))
            var shortDescription = JSONObject()
            shortDescription.set("text", .string(d.description))
            rule.set("shortDescription", .object(shortDescription))
            var defaultConfiguration = JSONObject()
            defaultConfiguration.set("level", .string(defaultLevelForDetector(d.id)))
            rule.set("defaultConfiguration", .object(defaultConfiguration))
            return .object(rule)
        }

        let results: [JSONValue] = audit.findings.map { f in
            var result = JSONObject()
            result.set("ruleId", .string(f.ruleId))
            result.set("level", .string(severityToLevel(f.severity)))
            var message = JSONObject()
            message.set("text", .string("\(f.variable): \(f.message)"))
            result.set("message", .object(message))
            let locations: [JSONValue] = f.locations.map { loc in
                var physicalLocation = JSONObject()
                var artifactLocation = JSONObject()
                artifactLocation.set("uri", .string(normalizePath(displayPath(rootDir, loc.filePath))))
                physicalLocation.set("artifactLocation", .object(artifactLocation))
                if let line = loc.line, line > 0 {
                    var region = JSONObject()
                    region.set("startLine", .int(line))
                    physicalLocation.set("region", .object(region))
                }
                var location = JSONObject()
                location.set("physicalLocation", .object(physicalLocation))
                return .object(location)
            }
            result.set("locations", .array(locations))
            return .object(result)
        }

        var driver = JSONObject()
        driver.set("name", .string("envdoctor"))
        driver.set("informationUri", .string("https://github.com/arun-skg/envdoctor"))
        driver.set("rules", .array(rules))

        var tool = JSONObject()
        tool.set("driver", .object(driver))

        var run = JSONObject()
        run.set("tool", .object(tool))
        run.set("results", .array(results))

        var root = JSONObject()
        root.set("$schema", .string(sarifSchema))
        root.set("version", .string("2.1.0"))
        root.set("runs", .array([.object(run)]))

        return .object(root)
    }
}
