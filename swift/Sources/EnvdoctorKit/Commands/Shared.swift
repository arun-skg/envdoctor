import Foundation

/// Resolve a `--dir`/`--root` argument to an absolute path.
public func resolveRoot(_ input: String?) -> String {
    let dir = resolvePath(FileManager.default.currentDirectoryPath, input ?? ".")
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory), isDirectory.boolValue else {
        // Matches the reference's resolveRootDir: "Directory not found: <dir>"
        // (a file that exists hits the same message in the reference's
        // commander wrapper path; treat uniformly).
        FileHandle.standardError.write("error: Directory not found: \(dir)\n")
        exit(2)
    }
    return dir
}

/// Resolve a possibly-relative path against a base, normalizing `.`/`..`
/// components without requiring the path to exist.
public func resolvePath(_ base: String, _ path: String) -> String {
    if path.hasPrefix("/") {
        return normalizeAbsolute(path)
    }
    return normalizeAbsolute(base + "/" + path)
}

private func normalizeAbsolute(_ p: String) -> String {
    var parts: [String] = []
    for component in p.split(separator: "/", omittingEmptySubsequences: true) {
        if component == "." { continue }
        if component == ".." {
            if !parts.isEmpty { parts.removeLast() }
            continue
        }
        parts.append(String(component))
    }
    return "/" + parts.joined(separator: "/")
}

/// Report files that could not be parsed, without failing the command.
public func reportParseErrors(_ model: ProjectModel, _ rootDir: String) {
    for pe in model.parseErrors {
        FileHandle.standardError.write("⚠ \(displayPath(rootDir, pe.filePath)): \(pe.error)\n")
    }
}

/// Write a file, creating parent directories.
public func writeFile(at path: String, content: String) throws {
    let dir = (path as NSString).deletingLastPathComponent
    if !dir.isEmpty {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    try content.write(toFile: path, atomically: true, encoding: .utf8)
}

/// The normalized environment label for a user-supplied diff/sync argument.
public func normalizeEnvLabel(_ label: String) -> String {
    let trimmed = label.trimmingCharacters(in: .whitespaces)
    if trimmed == "dev" { return "development" }
    if trimmed == "prod" { return "production" }
    return trimmed
}

/// JS `String.prototype.padEnd` — pad with spaces, never truncate.
public func padEnd(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return s + String(repeating: " ", count: width - s.count)
}

/// JS `String.prototype.padStart` — left-pad with spaces, never truncate.
public func padStart(_ s: String, _ width: Int) -> String {
    if s.count >= width { return s }
    return String(repeating: " ", count: width - s.count) + s
}
