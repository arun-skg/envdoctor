import Foundation

/// A file that a parser claimed during discovery.
public struct DiscoveredFile {
    /// Absolute path to the file.
    public var filePath: String
    public var parser: Parser
}

/// File discovery for the audit pipeline: walk the project tree and match
/// against the config's glob patterns, skipping always-ignored directories and
/// the user's `ignoreFiles`.
public enum Discover {
    /// Directories that are never descended into (the reference's ignore
    /// list); none of them hold project env files.
    private static let ignoredDirs: Set<String> = [
        "node_modules", ".git", "dist", "build", "coverage", ".next", ".nuxt",
        ".venv", "vendor", ".Trash", "Library", ".cache", ".npm",
    ]

    /// Discover every file that any parser claims, using the config's glob
    /// patterns. Results are sorted ordinal for deterministic output, matching
    /// the effective order of the reference implementations.
    public static func discoverFiles(
        _ rootDir: String,
        _ config: EnvdoctorConfig,
        _ registry: [Parser],
        gitFilter: GitFilterOptions? = nil
    ) -> [DiscoveredFile] {
        let patterns = config.envFilePatterns
            + config.composeFilePatterns
            + config.actionsFilePatterns
            + config.k8sFilePatterns

        var changedFiles: Set<String>? = nil
        if let gitFilter {
            if let since = gitFilter.since {
                changedFiles = Git.changedFilesSince(rootDir, since)
            } else if gitFilter.staged {
                changedFiles = Git.stagedFiles(rootDir)
            }
        }

        let allFiles = walkFiles(rootDir)
        var discovered: [DiscoveredFile] = []
        var seen = Set<String>()

        for path in allFiles {
            let rel = relativePath(rootDir, path)

            // The registry assigns each file to the first parser whose
            // `match` claims it; discovery additionally requires the file to
            // match one of the config's path globs (mirroring fast-glob in the
            // reference, which matches against the lexical walk path).
            // Source files are extension-matched by the registry, which is
            // equivalent to their `**/*.{ext}` discovery glob.
            guard let parser = parserForPath(registry, path) else { continue }
            if !(parser is SourceParser) {
                guard patterns.contains(where: { PathGlob.matches($0, rel) }) else { continue }
            }
            // User-ignored files.
            if Glob.matchesAnyGlob(config.ignoreFiles, rel) { continue }

            // The reference resolves symlinks per matched file
            // (fs.realpathSync), so e.g. macOS /tmp reports as /private/tmp.
            // NSString.resolvingSymlinksInPath only readlinks and misses
            // firmlinks, so use realpath(3) like Node does.
            let realPath = Discover.realpath(path) ?? path
            if !seen.insert(realPath).inserted { continue }
            if let changedFiles, !changedFiles.contains(realPath) { continue }
            discovered.append(DiscoveredFile(filePath: realPath, parser: parser))
        }

        discovered.sort { $0.filePath < $1.filePath }
        return discovered
    }

    /// Walk every file under root, pruning always-ignored directories.
    private static func walkFiles(_ root: String) -> [String] {
        var results: [String] = []
        var pending: [String] = [root]
        let fm = FileManager.default
        while let dir = pending.popLast() {
            let entries: [String]
            do {
                entries = try fm.contentsOfDirectory(atPath: dir)
            } catch {
                continue
            }
            // Sort for deterministic traversal (fast-glob returns readdir
            // order; the final discovered list is sorted ordinal anyway).
            for name in entries.sorted() {
                let path = dir.hasSuffix("/") ? dir + name : dir + "/" + name
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    if !ignoredDirs.contains(name) {
                        pending.append(path.hasSuffix("/") ? path : path + "/")
                    }
                } else {
                    results.append(path)
                }
            }
        }
        return results
    }

    /// realpath(3): resolves symlinks and firmlinks exactly like Node's
    /// fs.realpathSync.
    static func realpath(_ path: String) -> String? {
        guard let resolved = Darwin.realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
