import Foundation

public struct ProjectContext {
    public var rootDir: String
    public var config: EnvdoctorConfig
    public var model: ProjectModel
}

/// The standard pipeline every command uses: load config → build parsers →
/// discover files → assemble the normalized model.
public enum Pipeline {
    public static func loadProject(_ rootDir: String, gitFilter: GitFilterOptions? = nil) throws -> ProjectContext {
        let config = try ConfigLoader.loadConfig(rootDir)
        let registry = defaultRegistry(sourceExtensions: config.sourceExtensions)
        let discovered = Discover.discoverFiles(rootDir, config, registry, gitFilter: gitFilter)
        let model = assembleModel(rootDir, config, discovered)
        return ProjectContext(rootDir: rootDir, config: config, model: model)
    }

    /// Distinct variable count across the whole model (names only).
    public static func distinctVariableCount(_ model: ProjectModel) -> Int {
        var names = Set<String>()
        for file in model.allFiles {
            for v in file.variables { names.insert(v.name) }
            for v in file.usages { names.insert(v.name) }
        }
        return names.count
    }
}
