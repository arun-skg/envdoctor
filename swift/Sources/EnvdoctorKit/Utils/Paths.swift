import Foundation

/// Render a path relative to the project root when possible, falling back to
/// the absolute path.
public func displayPath(_ rootDir: String, _ filePath: String) -> String {
    let rel = relativePath(rootDir, filePath)
    if rel.isEmpty || rel.hasPrefix("../") || rel == ".." || rel.hasPrefix("/") {
        return filePath
    }
    return rel
}

/// `path.relative`-style computation using POSIX separators.
public func relativePath(_ rootDir: String, _ filePath: String) -> String {
    let root = rootDir.hasSuffix("/") ? String(rootDir.dropLast()) : rootDir
    let file = filePath.hasSuffix("/") ? String(filePath.dropLast()) : filePath
    if file == root { return "" }
    let prefix = root + "/"
    if file.hasPrefix(prefix) {
        return String(file.dropFirst(prefix.count))
    }
    // General fallback: resolve ".." components lexically.
    let rootParts = root.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    let fileParts = file.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    var common = 0
    while common < rootParts.count, common < fileParts.count, rootParts[common] == fileParts[common] {
        common += 1
    }
    var rel: [String] = []
    rel.append(contentsOf: repeatElement("..", count: rootParts.count - common))
    rel.append(contentsOf: fileParts[common...])
    return rel.joined(separator: "/")
}

/// Join paths with platform separators, normalizing to forward slashes.
public func normalizePath(_ p: String) -> String {
    p.replacingOccurrences(of: "\\", with: "/")
}
