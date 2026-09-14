import Foundation

public enum GenerateTarget: String {
    case envExample = "env-example"
    case envDoc = "env-doc"
    case envTypes = "env-types"
    case configSchema = "config-schema"
    case configTemplate = "config-template"
    case githubActions = "github-actions"
}

public struct GenerateArgs {
    public var target: GenerateTarget
    public var root: String?
    public var output: String?

    public init(target: GenerateTarget) {
        self.target = target
    }
}

public enum GenerateCommand {
    /// `envdoctor generate <target>` — render a generator's output to stdout
    /// or a file.
    public static func run(_ args: GenerateArgs) throws -> Int {
        let root = resolveRoot(args.root)
        let context = try Pipeline.loadProject(root)

        let output: String
        switch args.target {
        case .envExample:
            output = EnvExampleGenerator.generateEnvExample(context.model)
        case .envDoc:
            output = EnvironmentDocGenerator.generateEnvironmentDoc(context.model)
        case .envTypes:
            output = EnvTypesGenerator.generateEnvTypes(context.model)
        case .configSchema:
            output = SchemaGenerator.generateConfigSchema()
        case .configTemplate:
            output = SchemaGenerator.generateConfigTemplate()
        case .githubActions:
            output = GithubActionsGenerator.generateGithubActions(context.model, config: context.config)
        }

        if let path = args.output {
            try writeFile(at: resolvePath(root, path), content: output)
            print("Written to \(path)")
        } else {
            print(output)
        }

        return 0
    }
}
