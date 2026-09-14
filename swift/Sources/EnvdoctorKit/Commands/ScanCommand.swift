import Foundation

public enum OutputFormat: String {
    case human, json, sarif
}

public struct ScanArgs {
    public var root: String?
    public var format: OutputFormat = .human
    public var strict = false
    public var verbose = false
    public var only: [String] = []
    public var baseline: String?
    public var writeBaseline: String?
    public var staged = false
    public var since: String?
    /// Write the rendered output to a file instead of stdout (port addition).
    public var output: String?

    public init() {}
}

public enum ScanCommand {
    /// `envdoctor scan` — discover, parse, audit, and report.
    public static func run(_ args: ScanArgs) throws -> Int {
        let root = resolveRoot(args.root)

        // Warn about unknown detector ids passed via --only.
        let known = Audit.allDetectors.map(\.id)
        for rule in args.only where !known.contains(rule) {
            FileHandle.standardError.write("warning Unknown detector \"\(rule)\" (known: \(known.joined(separator: ", ")))\n")
        }

        let gitFilter: GitFilterOptions? = args.staged
            ? GitFilterOptions(staged: true)
            : args.since.map { GitFilterOptions(since: $0) }

        if let gitFilter, Git.hasNoGitChanges(root, gitFilter) {
            print("✓ No changed env-related files to scan")
            return 0
        }

        let context = try Pipeline.loadProject(root, gitFilter: gitFilter)
        var audit = Audit.runAudit(context.model, options: AuditOptions(
            strict: args.strict,
            only: args.only,
            rules: context.config.rules
        ))

        reportParseErrors(context.model, root)

        if let baseline = args.baseline {
            audit = applyBaseline(audit, baseline, root, args.strict)
        }

        if let writeBaseline = args.writeBaseline {
            writeBaselineFile(audit, writeBaseline, root)
        }

        let rendered: String
        switch args.format {
        case .json:
            rendered = ScanJsonFormatter.render(audit, rootDir: root)
        case .sarif:
            rendered = SarifFormatter.renderSarif(audit, rootDir: root)
        case .human:
            rendered = HumanFormatter.renderReport(audit, rootDir: root, verbose: args.verbose)
        }

        if let output = args.output {
            try writeFile(at: output, content: rendered)
        } else {
            print(rendered)
        }

        return audit.exitCode
    }

    // MARK: - Baselines

    private struct BaselineEntry {
        var ruleId: String
        var variable: String
        var files: [String]
    }

    private static func fingerprint(_ root: String, _ finding: Finding) -> BaselineEntry {
        let files = Array(Set(finding.locations.map { displayPath(root, $0.filePath) })).sorted()
        return BaselineEntry(ruleId: finding.ruleId, variable: finding.variable, files: files)
    }

    private static func applyBaseline(_ audit: AuditResult, _ baselinePath: String, _ root: String, _ strict: Bool) -> AuditResult {
        let fullPath = resolvePath(root, baselinePath)
        struct BaselineFile { var version: Int; var findings: [BaselineEntry] }
        let baseline: BaselineFile?
        do {
            let raw = try String(contentsOfFile: fullPath, encoding: .utf8)
            guard case .object(let obj) = try JsonParser.parse(raw) else { throw JsonParser.Error(description: "not an object") }
            var version = 0
            if case .int(let v)? = obj["version"] { version = v }
            var entries: [BaselineEntry] = []
            if case .array(let findings)? = obj["findings"] {
                for f in findings {
                    guard case .object(let fo) = f else { continue }
                    let ruleId = fo["ruleId"]?.asString ?? ""
                    let variable = fo["variable"]?.asString ?? ""
                    let files = fo["files"]?.asArray?.map { $0.asString ?? "" } ?? []
                    entries.append(BaselineEntry(ruleId: ruleId, variable: variable, files: files))
                }
            }
            baseline = BaselineFile(version: version, findings: entries)
        } catch {
            FileHandle.standardError.write("warning Could not read baseline \(baselinePath): \(error.localizedDescription)\n")
            baseline = nil
        }

        guard let baseline else { return audit }

        func matches(_ a: BaselineEntry, _ b: BaselineEntry) -> Bool {
            a.ruleId == b.ruleId && a.variable == b.variable && a.files == b.files
        }

        let before = audit.findings.count
        let findings = audit.findings.filter { f in
            let fp = fingerprint(root, f)
            return !baseline.findings.contains { matches($0, fp) }
        }
        let suppressed = before - findings.count
        if suppressed > 0 {
            FileHandle.standardError.write("info \(suppressed) finding\(suppressed == 1 ? "" : "s") suppressed by baseline\n")
        }

        return recomputeAudit(audit, findings, strict)
    }

    private static func recomputeAudit(_ audit: AuditResult, _ findings: [Finding], _ strict: Bool) -> AuditResult {
        let summary = AuditSummary(
            filesScanned: audit.summary.filesScanned,
            variablesFound: audit.summary.variablesFound,
            errors: findings.filter { $0.severity == .error }.count,
            warnings: findings.filter { $0.severity == .warning }.count,
            infos: findings.filter { $0.severity == .info }.count,
            total: findings.count
        )
        let exitCode = (summary.errors > 0 || (strict && summary.warnings > 0)) ? 1 : 0
        return AuditResult(findings: findings, summary: summary, exitCode: exitCode)
    }

    private static func writeBaselineFile(_ audit: AuditResult, _ baselinePath: String, _ root: String) {
        let fullPath = resolvePath(root, baselinePath)
        var baseline = JSONObject()
        baseline.set("version", .int(1))
        baseline.set("findings", .array(audit.findings.map { f in
            let fp = fingerprint(root, f)
            var entry = JSONObject()
            entry.set("ruleId", .string(fp.ruleId))
            entry.set("variable", .string(fp.variable))
            entry.set("files", .array(fp.files.map { .string($0) }))
            return .object(entry)
        }))
        let dir = (fullPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? writeFile(at: fullPath, content: Json.pretty(.object(baseline)) + "\n")
        FileHandle.standardError.write("info Wrote baseline to \(baselinePath)\n")
    }
}
