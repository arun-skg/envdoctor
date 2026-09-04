using System.Text.Json;

namespace Envdoctor.Config;

public sealed class ConfigError : Exception
{
    public ConfigError(string message) : base(message) { }
}

public static class ConfigLoader
{
    private static readonly string[] ConfigBasenames = { "envdoctor.config.toml", "envdoctor.config.json" };

    /// Load and validate the config for a project root. Falls back to defaults
    /// when no config exists. Throws `ConfigError` when a config file is
    /// present but invalid.
    public static EnvdoctorConfig LoadConfig(string rootDir)
    {
        var configPath = FindConfigFile(rootDir);
        var pkgConfig = ReadPackageJsonConfig(rootDir);

        if (configPath is null && pkgConfig is null)
            return new EnvdoctorConfig();

        Dictionary<string, object?> raw;
        if (configPath is not null)
        {
            string content;
            try
            {
                content = File.ReadAllText(configPath);
            }
            catch (Exception e)
            {
                throw new ConfigError(
                    $"Could not load config {configPath}: {e.Message}. Use envdoctor.config.toml (or package.json#envdoctor).");
            }

            try
            {
                if (Path.GetExtension(configPath) == ".toml")
                {
                    var table = Tomlyn.Toml.ToModel(content);
                    raw = (Dictionary<string, object?>)TomlToPlain(table)!;
                }
                else
                {
                    raw = (Dictionary<string, object?>)JsonToPlain(JsonDocument.Parse(content).RootElement)!;
                }
            }
            catch (Exception e) when (e is not ConfigError)
            {
                throw new ConfigError($"Invalid envdoctor config: {e.Message}");
            }
        }
        else
        {
            raw = pkgConfig!;
        }

        try
        {
            return MapConfig(raw);
        }
        catch (Exception e) when (e is not ConfigError)
        {
            throw new ConfigError($"Invalid envdoctor config: {e.Message}");
        }
    }

    /// Like <see cref="LoadConfig"/> but silently falls back to defaults on error,
    /// matching the reference pipeline's `unwrap_or_default()`.
    public static EnvdoctorConfig LoadConfigOrDefault(string rootDir)
    {
        try
        {
            return LoadConfig(rootDir);
        }
        catch (ConfigError)
        {
            return new EnvdoctorConfig();
        }
    }

    private static string? FindConfigFile(string rootDir)
    {
        foreach (var basename in ConfigBasenames)
        {
            var candidate = Path.Combine(rootDir, basename);
            if (File.Exists(candidate))
                return candidate;
        }
        return null;
    }

    private static Dictionary<string, object?>? ReadPackageJsonConfig(string rootDir)
    {
        try
        {
            var content = File.ReadAllText(Path.Combine(rootDir, "package.json"));
            var doc = JsonDocument.Parse(content);
            if (doc.RootElement.ValueKind == JsonValueKind.Object &&
                doc.RootElement.TryGetProperty("envdoctor", out var section) &&
                section.ValueKind == JsonValueKind.Object)
            {
                return (Dictionary<string, object?>)JsonToPlain(section)!;
            }
        }
        catch
        {
            // no package.json or unreadable — treat as absent
        }
        return null;
    }

    private static object? JsonToPlain(JsonElement el) => el.ValueKind switch
    {
        JsonValueKind.Object => el.EnumerateObject()
            .ToDictionary(p => p.Name, p => JsonToPlain(p.Value)),
        JsonValueKind.Array => el.EnumerateArray().Select(JsonToPlain).ToList(),
        JsonValueKind.String => el.GetString(),
        JsonValueKind.Number => el.TryGetInt64(out var l) ? l : el.GetDouble(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        _ => null,
    };

    private static object? TomlToPlain(object? value) => value switch
    {
        Tomlyn.Model.TomlTable table => table.ToDictionary(
            kv => kv.Key,
            kv => TomlToPlain(kv.Value)),
        Tomlyn.Model.TomlArray array => array.Select(TomlToPlain).ToList(),
        _ => value,
    };

    private static EnvdoctorConfig MapConfig(Dictionary<string, object?> raw)
    {
        var config = new EnvdoctorConfig();
        foreach (var (key, value) in raw)
        {
            switch (key)
            {
                case "envFilePatterns": config.EnvFilePatterns = AsStringList(value); break;
                case "composeFilePatterns": config.ComposeFilePatterns = AsStringList(value); break;
                case "actionsFilePatterns": config.ActionsFilePatterns = AsStringList(value); break;
                case "k8sFilePatterns": config.K8sFilePatterns = AsStringList(value); break;
                case "sourceExtensions": config.SourceExtensions = AsStringList(value); break;
                case "ignoreVariables": config.IgnoreVariables = AsStringList(value); break;
                case "ignoreFiles": config.IgnoreFiles = AsStringList(value); break;
                case "environments":
                    config.Environments = AsMap(value).ToDictionary(kv => kv.Key, kv => AsStringList(kv.Value));
                    break;
                case "strict": config.Strict = AsBool(value); break;
                case "rules":
                    config.Rules = AsMap(value).ToDictionary(kv => kv.Key, kv => ParseRuleSeverity(kv.Value));
                    break;
                case "schema":
                    config.Schema = AsMap(value).ToDictionary(kv => kv.Key, kv => ParseVariableSchema(kv.Value));
                    break;
                default:
                    // Unknown keys are ignored, matching serde's default behavior.
                    break;
            }
        }
        return config;
    }

    private static Dictionary<string, object?> AsMap(object? value) =>
        value as Dictionary<string, object?> ?? throw new InvalidDataException("expected a table/object");

    private static List<string> AsStringList(object? value)
    {
        if (value is not List<object?> list)
            throw new InvalidDataException("expected an array of strings");
        return list.Select(v => v as string ?? throw new InvalidDataException("expected a string")).ToList();
    }

    private static bool AsBool(object? value) =>
        value as bool? ?? throw new InvalidDataException("expected a boolean");

    private static RuleSeverity ParseRuleSeverity(object? value) =>
        (value as string) switch
        {
            "error" => RuleSeverity.Error,
            "warning" => RuleSeverity.Warning,
            "off" => RuleSeverity.Off,
            _ => throw new InvalidDataException("expected \"error\", \"warning\", or \"off\""),
        };

    private static VariableSchema ParseVariableSchema(object? value)
    {
        var map = AsMap(value);
        var schema = new VariableSchema();
        foreach (var (key, v) in map)
        {
            switch (key)
            {
                case "type":
                    schema.VarType = (v as string) switch
                    {
                        "string" => SchemaType.String,
                        "integer" => SchemaType.Integer,
                        "float" => SchemaType.Float,
                        "boolean" => SchemaType.Boolean,
                        "url" => SchemaType.Url,
                        "json" => SchemaType.Json,
                        "enum" => SchemaType.Enum,
                        "regex" => SchemaType.Regex,
                        _ => throw new InvalidDataException("unknown schema type"),
                    };
                    break;
                case "optional": schema.Optional = AsBool(v); break;
                case "enum":
                case "enumValues":
                    schema.EnumValues = AsStringList(v);
                    break;
                case "regex": schema.Regex = v as string; break;
                case "min": schema.Min = AsLong(v); break;
                case "max": schema.Max = AsLong(v); break;
            }
        }
        return schema;
    }

    private static long AsLong(object? value) => value switch
    {
        long l => l,
        int i => i,
        double d => (long)d,
        _ => throw new InvalidDataException("expected an integer"),
    };
}
