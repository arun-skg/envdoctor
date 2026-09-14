import Foundation

public struct GitFilterOptions {
    public var since: String?
    public var staged: Bool

    public init(since: String? = nil, staged: Bool = false) {
        self.since = since
        self.staged = staged
    }
}

public enum Git {
    private static func gitTopLevel(_ cwd: String) -> String? {
        guard let raw = runGit(cwd, ["rev-parse", "--show-toplevel"]) else { return nil }
        let top = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return top.isEmpty ? nil : top
    }

    private static func runGit(_ cwd: String, _ args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func addResolvedPaths(_ topLevel: String, _ stdout: String, _ files: inout Set<String>) {
        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let resolved = resolvePath((topLevel as NSString).appendingPathComponent(trimmed))
            files.insert(resolved)
        }
    }

    static func resolvePath(_ p: String) -> String {
        // Resolve symlinks like fs.realpathSync, without requiring existence checks beyond what FileManager offers.
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: p) {
            if dest.hasPrefix("/") {
                return resolvePath(dest)
            }
            let dir = (p as NSString).deletingLastPathComponent
            return resolvePath((dir as NSString).appendingPathComponent(dest))
        }
        // Standardize (resolve .. and . lexically), matching realpath behavior for existing files.
        let standardized = (p as NSString).standardizingPath
        // StandardizingPath strips duplicate slashes; realpath keeps the leading ones. For
        // our purposes (matching against other realpaths) this is sufficient.
        return standardized
    }

    private static func changedFiles(_ cwd: String, _ args: [String], includeUntracked: Bool) -> Set<String>? {
        guard let topLevel = gitTopLevel(cwd) else { return nil }
        guard let stdout = runGit(topLevel, ["-C", topLevel, "diff", "--name-only"] + args) else { return nil }
        var files = Set<String>()
        addResolvedPaths(topLevel, stdout, &files)
        if includeUntracked {
            if let untracked = runGit(topLevel, ["-C", topLevel, "ls-files", "--others", "--exclude-standard"]) {
                addResolvedPaths(topLevel, untracked, &files)
            }
        }
        return files
    }

    /// Absolute paths of files changed since `ref`, including untracked files.
    public static func changedFilesSince(_ cwd: String, _ ref: String) -> Set<String>? {
        changedFiles(cwd, [ref], includeUntracked: true)
    }

    /// Absolute paths of files staged for commit.
    public static func stagedFiles(_ cwd: String) -> Set<String>? {
        changedFiles(cwd, ["--cached"], includeUntracked: false)
    }

    /// True when git-aware filtering is active but no git changes were found.
    public static func hasNoGitChanges(_ cwd: String, _ filter: GitFilterOptions) -> Bool {
        if filter.staged {
            guard let files = stagedFiles(cwd) else { return false }
            return files.isEmpty
        }
        if let since = filter.since {
            guard let files = changedFilesSince(cwd, since) else { return false }
            return files.isEmpty
        }
        return false
    }
}
