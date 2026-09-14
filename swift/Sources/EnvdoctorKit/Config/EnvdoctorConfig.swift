import Foundation

public enum RuleSeverity: String {
    case error, warning, off
}

public enum SchemaType: String {
    case string, integer, float, boolean, url, json, `enum`, regex
}

public struct VariableSchema {
    public var type: SchemaType?
    public var optional: Bool?
    public var enumValues: [String]?
    public var regex: String?
    public var min: Double?
    public var max: Double?

    public init() {}
}

public struct EnvdoctorConfig {
    /// Glob patterns (relative to the project root) for dotenv files.
    public var envFilePatterns: [String]
    /// Glob patterns for docker-compose files.
    public var composeFilePatterns: [String]
    /// Glob patterns for GitHub Actions workflows.
    public var actionsFilePatterns: [String]
    /// Glob patterns for Kubernetes manifests.
    public var k8sFilePatterns: [String]
    /// File extensions scanned for source usage.
    public var sourceExtensions: [String]
    /// Glob patterns of variable names to never report (e.g. "AWS_*").
    public var ignoreVariables: [String]
    /// Glob patterns of files to skip.
    public var ignoreFiles: [String]
    /// Explicit environment label → file mapping.
    public var environments: [String: [String]]?
    /// Fail the audit when only warnings are present.
    public var strict: Bool
    /// Override severity per detector. Use "off" to disable a detector.
    public var rules: [String: RuleSeverity]
    /// Per-variable validation schema.
    public var schema: [String: VariableSchema]

    public init(
        envFilePatterns: [String] = [".env", ".env.*"],
        composeFilePatterns: [String] = ["**/docker-compose*.y*ml", "**/compose*.y*ml"],
        actionsFilePatterns: [String] = [".github/workflows/**/*.y*ml"],
        k8sFilePatterns: [String] = [
            "**/*.{deployment,service,statefulset,daemonset,cronjob,job,configmap,secret,ingress,pvc}.y*ml",
            "**/k8s/**/*.y*ml",
            "**/kubernetes/**/*.y*ml",
            "**/manifests/**/*.y*ml",
            "**/deploy/**/*.y*ml",
        ],
        sourceExtensions: [String] = ["ts", "tsx", "js", "jsx", "mjs", "cjs"],
        ignoreVariables: [String] = [],
        ignoreFiles: [String] = [],
        environments: [String: [String]]? = nil,
        strict: Bool = false,
        rules: [String: RuleSeverity] = [:],
        schema: [String: VariableSchema] = [:]
    ) {
        self.envFilePatterns = envFilePatterns
        self.composeFilePatterns = composeFilePatterns
        self.actionsFilePatterns = actionsFilePatterns
        self.k8sFilePatterns = k8sFilePatterns
        self.sourceExtensions = sourceExtensions
        self.ignoreVariables = ignoreVariables
        self.ignoreFiles = ignoreFiles
        self.environments = environments
        self.strict = strict
        self.rules = rules
        self.schema = schema
    }
}
