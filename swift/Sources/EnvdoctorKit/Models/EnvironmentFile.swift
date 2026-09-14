import Foundation

public enum FileFormat: String {
    case dotenv, dockerCompose = "docker-compose", githubActions = "github-actions", kubernetes, source
}

/// The parsed contents of a single file, normalized to envdoctor's model.
public struct EnvironmentFile {
    /// Path the file was read from.
    public var filePath: String
    public var format: FileFormat
    /// Environment label for dotenv files ("development", "production", ...).
    public var environment: String?
    public var variables: [EnvironmentVariable]
    public var usages: [EnvironmentVariable]

    public init(filePath: String, format: FileFormat, environment: String? = nil, variables: [EnvironmentVariable], usages: [EnvironmentVariable]) {
        self.filePath = filePath
        self.format = format
        self.environment = environment
        self.variables = variables
        self.usages = usages
    }
}

/// Names defined in a file, deduplicated, in first-seen order.
public func definedNames(_ file: EnvironmentFile) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for v in file.variables where !seen.contains(v.name) {
        seen.insert(v.name)
        out.append(v.name)
    }
    return out
}

/// Names used in a file, deduplicated, in first-seen order.
public func usedNames(_ file: EnvironmentFile) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for v in file.usages where !seen.contains(v.name) {
        seen.insert(v.name)
        out.append(v.name)
    }
    return out
}
