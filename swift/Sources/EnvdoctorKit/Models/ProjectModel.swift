import Foundation

/// The fully assembled, format-agnostic view of a project. This is the single
/// input to the audit engine — detectors never look at raw file formats.
public struct ProjectModel {
    /// The project root the model was built from.
    public var rootDir: String
    /// The resolved envdoctor config for this project.
    public var config: EnvdoctorConfig
    /// Parsed `.env*` files, each tagged with an environment label.
    public var envFiles: [EnvironmentFile]
    /// Parsed docker-compose files.
    public var composeFiles: [EnvironmentFile]
    /// Parsed GitHub Actions workflow files.
    public var actionFiles: [EnvironmentFile]
    /// Parsed Kubernetes manifest files.
    public var k8sFiles: [EnvironmentFile]
    /// Source code files scanned for `process.env` / `import.meta.env` usage.
    public var sourceFiles: [EnvironmentFile]
    /// Every file that was scanned, in any format.
    public var allFiles: [EnvironmentFile]
    /// Files that matched a parser but failed to parse (kept for reporting).
    public var parseErrors: [(filePath: String, error: String)]

    public init(rootDir: String, config: EnvdoctorConfig, envFiles: [EnvironmentFile], composeFiles: [EnvironmentFile], actionFiles: [EnvironmentFile], k8sFiles: [EnvironmentFile], sourceFiles: [EnvironmentFile], allFiles: [EnvironmentFile], parseErrors: [(filePath: String, error: String)]) {
        self.rootDir = rootDir
        self.config = config
        self.envFiles = envFiles
        self.composeFiles = composeFiles
        self.actionFiles = actionFiles
        self.k8sFiles = k8sFiles
        self.sourceFiles = sourceFiles
        self.allFiles = allFiles
        self.parseErrors = parseErrors
    }
}

/// All definitions (variables with values) across the whole project.
public func allDefinitions(_ model: ProjectModel) -> [EnvironmentVariable] {
    model.envFiles.flatMap(\.variables) + model.composeFiles.flatMap(\.variables) + model.actionFiles.flatMap(\.variables)
}

/// All usages (name references without values) across the whole project.
public func allUsages(_ model: ProjectModel) -> [EnvironmentVariable] {
    model.envFiles.flatMap(\.usages) + model.composeFiles.flatMap(\.usages) + model.actionFiles.flatMap(\.usages) + model.sourceFiles.flatMap(\.usages)
}

/// Flatten every origin for a name into a deduplicated list.
public func originsForName(_ model: ProjectModel, _ name: String) -> [Origin] {
    var seen: [String: Origin] = [:]
    var order: [String] = []
    func consider(_ v: EnvironmentVariable) {
        guard v.name == name else { return }
        for origin in v.origins {
            let key = "\(origin.filePath):\(origin.line ?? 0):\(origin.kind.rawValue)"
            if seen[key] == nil {
                seen[key] = origin
                order.append(key)
            }
        }
    }
    for file in model.allFiles {
        file.variables.forEach(consider)
        file.usages.forEach(consider)
    }
    return order.compactMap { seen[$0] }
}
