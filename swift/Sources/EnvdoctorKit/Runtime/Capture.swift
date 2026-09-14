import Foundation

/// Live runtime capture. Only tool versions, PATH order, package names, and
/// non-secret env var NAMES are recorded — never any value.
public enum Capture {
    private static let versionRe = try! NSRegularExpression(pattern: #"(\d+\.\d+(?:\.\d+)?)"#)

    /// First dotted version-looking token in a tool's output.
    static func firstVersion(_ output: String) -> String? {
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = versionRe.firstMatch(in: output, range: range),
              let result = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[result])
    }

    /// Collapse a leading $HOME to "~" so snapshots don't leak usernames.
    public static func collapseHome(_ p: String) -> String {
        let home = NSHomeDirectory()
        if !home.isEmpty && (p == home || p.hasPrefix(home + "/")) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }

    /// Ordered, de-duplicated `$PATH` entries with $HOME collapsed.
    public static func collectPath(_ pathEnv: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in pathEnv.split(separator: ":", omittingEmptySubsequences: false) {
            if raw.isEmpty { continue }
            let entry = collapseHome(String(raw))
            if seen.contains(entry) { continue }
            seen.insert(entry)
            out.append(entry)
        }
        return out
    }

    /// Non-secret env var NAMES only. Secret-looking names are dropped, not masked.
    public static func collectEnvFlagNames(_ env: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        env.keys.filter { !isSecretName($0) }.sorted()
    }

    /// Probe one CLI's version; returns nil when the tool isn't installed or misbehaves.
    /// Some tools print `--version` to stderr (e.g. java), so scan both streams.
    static func probeVersion(_ tool: String, _ args: [String], timeout: TimeInterval = 4) -> String? {
        guard let (stdout, stderr) = runProcess("/usr/bin/env", [tool] + args, timeout: timeout) else { return nil }
        return firstVersion(stdout + "\n" + stderr)
    }

    /// Locate which PATH directory a command resolves from, $HOME collapsed.
    static func resolveFrom(_ tool: String) -> String {
        guard let (path, _) = runProcess("/usr/bin/env", ["which", tool]) else { return "" }
        guard let first = path.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else {
            return ""
        }
        return collapseHome((first as NSString).deletingLastPathComponent)
    }

    static func runProcess(_ executable: String, _ args: [String], timeout: TimeInterval = 4) -> (String, String)? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return nil
        }
        // Simple polling timeout — these are short-lived version probes.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (out, err)
    }

    /// Tools probed by default. Order here is the display order.
    static let toolProbes: [(String, [String])] = [
        ("node", ["-v"]),
        ("python3", ["--version"]),
        ("python", ["--version"]),
        ("go", ["version"]),
        ("rustc", ["-V"]),
        ("java", ["-version"]),
        ("ruby", ["-v"]),
        ("php", ["-v"]),
        ("perl", ["-v"]),
        ("cc", ["--version"]),
        ("git", ["--version"]),
    ]

    /// Probe every known tool; only installed ones appear in the result,
    /// sorted by tool id.
    public static func collectTools() -> [ToolVersion] {
        var results: [ToolVersion] = []
        for (tool, args) in toolProbes {
            guard let version = probeVersion(tool, args) else { continue }
            results.append(ToolVersion(tool: tool, version: version, resolvedFrom: resolveFrom(tool)))
        }
        return results.sorted { Locale.localeCompare($0.tool, $1.tool) < 0 }
    }

    /// Parse `npm ls -g --json` into a name/version list.
    static func parseNpmGlobals(_ stdout: String) -> [GlobalPackage] {
        guard case .object(let root)? = try? JsonParser.parse(stdout),
              case .object(let deps)? = root["dependencies"] else {
            return []
        }
        var packages: [GlobalPackage] = []
        for (name, meta) in deps.entries {
            let version = meta["version"]?.asString ?? ""
            packages.append(GlobalPackage(name: name, version: version))
        }
        return packages.sorted { Locale.localeCompare($0.name, $1.name) < 0 }
    }

    /// Global package inventory, opt-in (`--globals`). Best-effort per ecosystem.
    public static func collectGlobals() -> [(String, [GlobalPackage])] {
        guard let (stdout, _) = runProcess("/usr/bin/env", ["npm", "ls", "-g", "--depth=0", "--json"], timeout: 15) else {
            return []
        }
        let packages = parseNpmGlobals(stdout)
        if packages.isEmpty { return [] }
        return [("npm", packages)]
    }

    /// Capture this machine's live runtime into a snapshot.
    public static func captureSnapshot(globals: Bool = false) -> RuntimeSnapshot {
        let tools = collectTools()
        let globalsList = globals ? collectGlobals() : []

        var utsnameInfo = utsname()
        uname(&utsnameInfo)
        let release = withUnsafeBytes(of: &utsnameInfo.release) { buf in
            String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let machine = withUnsafeBytes(of: &utsnameInfo.machine) { buf in
            String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
        }

        #if os(Linux)
        let platform = "linux"
        #else
        let platform = "darwin"
        #endif

        return RuntimeSnapshot(
            schema: snapshotSchema,
            capturedAt: iso8601Now(),
            osPlatform: platform,
            osArch: machine,
            osRelease: release,
            tools: tools,
            path: collectPath(),
            globals: globalsList,
            envFlagNames: collectEnvFlagNames()
        )
    }

    /// `new Date().toISOString()`: milliseconds, UTC, `Z` suffix.
    static func iso8601Now() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: now)
        let millis = (components.nanosecond ?? 0) / 1_000_000
        func pad(_ n: Int, _ width: Int) -> String {
            let s = String(n)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(components.year ?? 0, 4))-\(pad(components.month ?? 0, 2))-\(pad(components.day ?? 0, 2))T\(pad(components.hour ?? 0, 2)):\(pad(components.minute ?? 0, 2)):\(pad(components.second ?? 0, 2)).\(pad(millis, 3))Z"
    }
}
