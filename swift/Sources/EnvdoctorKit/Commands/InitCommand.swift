import Foundation

public struct InitArgs {
    public var root: String?
    public var force = false

    public init() {}
}

public enum InitCommand {
    /// `envdoctor init` — bootstrap a config for the project. Non-destructive:
    /// an existing config is only overwritten with `--force`.
    public static func run(_ args: InitArgs) throws -> Int {
        let root = resolveRoot(args.root)
        let configPath = root + "/envdoctor.config.toml"

        if FileManager.default.fileExists(atPath: configPath), !args.force {
            FileHandle.standardError.write("Config already exists at \(configPath). Use --force to overwrite.\n")
            return 1
        }

        let template = SchemaGenerator.generateConfigTemplate()
        try template.write(toFile: configPath, atomically: true, encoding: .utf8)

        print("Created \(configPath)")
        print("Edit the file to customize your configuration, then run `envdoctor scan`.")

        return 0
    }
}
