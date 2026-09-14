import Foundation

/// Where a variable name was seen, and in what role.
public struct Origin: Equatable {
    public enum Kind: String, Equatable {
        case definition, reference, usage
    }

    public enum Format: String, Equatable {
        case dotenv, dockerCompose = "docker-compose", githubActions = "github-actions", kubernetes, source
    }

    /// Path to the file where the variable appeared (repo-relative when possible).
    public var filePath: String
    /// 1-based line number when known.
    public var line: Int?
    public var kind: Kind
    /// Environment label (dotenv files only, e.g. "development", "production").
    public var environment: String?
    /// The format the origin came from.
    public var format: Format?
    /// Format-specific detail (e.g. "secrets" vs "vars" for GitHub Actions).
    public var subkind: String?

    public init(filePath: String, line: Int? = nil, kind: Kind, environment: String? = nil, format: Format? = nil, subkind: String? = nil) {
        self.filePath = filePath
        self.line = line
        self.kind = kind
        self.environment = environment
        self.format = format
        self.subkind = subkind
    }
}
