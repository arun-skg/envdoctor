using Envdoctor.Models;

namespace Envdoctor.Config;

public enum RuleSeverity
{
    Error,
    Warning,
    Off,
}

public enum SchemaType
{
    String,
    Integer,
    Float,
    Boolean,
    Url,
    Json,
    Enum,
    Regex,
}

public static class SchemaTypeExtensions
{
    public static VariableType ToVariableType(this SchemaType t) => t switch
    {
        SchemaType.String => VariableType.String,
        SchemaType.Integer => VariableType.Integer,
        SchemaType.Float => VariableType.Float,
        SchemaType.Boolean => VariableType.Boolean,
        SchemaType.Url => VariableType.Url,
        SchemaType.Json => VariableType.Json,
        SchemaType.Enum => VariableType.String,
        SchemaType.Regex => VariableType.String,
        _ => VariableType.String,
    };

    public static string AsStr(this SchemaType t) => t switch
    {
        SchemaType.String => "string",
        SchemaType.Integer => "integer",
        SchemaType.Float => "float",
        SchemaType.Boolean => "boolean",
        SchemaType.Url => "url",
        SchemaType.Json => "json",
        SchemaType.Enum => "enum",
        SchemaType.Regex => "regex",
        _ => "string",
    };
}

public sealed class VariableSchema
{
    public SchemaType? VarType { get; set; }
    public bool? Optional { get; set; }
    public List<string>? EnumValues { get; set; }
    public string? Regex { get; set; }
    public long? Min { get; set; }
    public long? Max { get; set; }
}

/// envdoctor is configured through `envdoctor.config.toml|json` or a
/// `envdoctor` key in package.json. The config is optional — defaults are
/// sensible for most projects.
public sealed class EnvdoctorConfig
{
    public List<string> EnvFilePatterns { get; set; } = new() { ".env", ".env.*" };
    public List<string> ComposeFilePatterns { get; set; } = new() { "**/docker-compose*.y*ml", "**/compose*.y*ml" };
    public List<string> ActionsFilePatterns { get; set; } = new() { ".github/workflows/**/*.y*ml" };
    public List<string> K8sFilePatterns { get; set; } = new()
    {
        "**/*.{deployment,service,statefulset,daemonset,cronjob,job,configmap,secret,ingress,pvc}.y*ml",
        "**/k8s/**/*.y*ml",
        "**/kubernetes/**/*.y*ml",
        "**/manifests/**/*.y*ml",
        "**/deploy/**/*.y*ml",
    };
    public List<string> SourceExtensions { get; set; } = new() { "ts", "tsx", "js", "jsx", "mjs", "cjs" };
    public List<string> IgnoreVariables { get; set; } = new();
    public List<string> IgnoreFiles { get; set; } = new();
    public Dictionary<string, List<string>>? Environments { get; set; }
    public bool Strict { get; set; }
    public Dictionary<string, RuleSeverity> Rules { get; set; } = new();
    public Dictionary<string, VariableSchema> Schema { get; set; } = new();

    public EnvdoctorConfig Clone() =>
        new()
        {
            EnvFilePatterns = new List<string>(EnvFilePatterns),
            ComposeFilePatterns = new List<string>(ComposeFilePatterns),
            ActionsFilePatterns = new List<string>(ActionsFilePatterns),
            K8sFilePatterns = new List<string>(K8sFilePatterns),
            SourceExtensions = new List<string>(SourceExtensions),
            IgnoreVariables = new List<string>(IgnoreVariables),
            IgnoreFiles = new List<string>(IgnoreFiles),
            Environments = Environments?.ToDictionary(kv => kv.Key, kv => new List<string>(kv.Value)),
            Strict = Strict,
            Rules = new Dictionary<string, RuleSeverity>(Rules),
            Schema = Schema.ToDictionary(
                kv => kv.Key,
                kv => new VariableSchema
                {
                    VarType = kv.Value.VarType,
                    Optional = kv.Value.Optional,
                    EnumValues = kv.Value.EnumValues is null ? null : new List<string>(kv.Value.EnumValues),
                    Regex = kv.Value.Regex,
                    Min = kv.Value.Min,
                    Max = kv.Value.Max,
                }),
        };
}
