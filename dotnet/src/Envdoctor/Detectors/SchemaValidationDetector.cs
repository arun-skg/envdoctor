using System.Text.Json;
using System.Text.RegularExpressions;
using Envdoctor.Config;
using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Schema-validation: a variable value does not match its declared schema.
public sealed class SchemaValidationDetector : IDetector
{
    public string Id => "schema-validation";
    public string Name => "schema-validation";
    public string Description => "A variable value does not match its declared schema.";

    private delegate string? Validator(string value);

    /// Build a validator for a variable schema; returns null on success.
    private static Validator? BuildValidator(VariableSchema schema)
    {
        if (schema.EnumValues is { Count: > 0 } enumValues)
        {
            var values = enumValues.ToList();
            return v => values.Contains(v) ? null : $"must be one of: {string.Join(", ", values)}";
        }

        switch (schema.VarType)
        {
            case SchemaType.Integer:
            {
                var min = schema.Min;
                var max = schema.Max;
                return v =>
                {
                    if (!long.TryParse(v, System.Globalization.NumberStyles.Integer,
                            System.Globalization.CultureInfo.InvariantCulture, out var n))
                        return "must be an integer";
                    if (min is not null && n < min.Value)
                        return $"must be >= {min.Value}";
                    if (max is not null && n > max.Value)
                        return $"must be <= {max.Value}";
                    return null;
                };
            }
            case SchemaType.Float:
            {
                var min = schema.Min;
                var max = schema.Max;
                return v =>
                {
                    if (!double.TryParse(v, System.Globalization.NumberStyles.Float,
                            System.Globalization.CultureInfo.InvariantCulture, out var n))
                        return "must be a float";
                    if (min is not null && n < min.Value)
                        return $"must be >= {min.Value}";
                    if (max is not null && n > max.Value)
                        return $"must be <= {max.Value}";
                    return null;
                };
            }
            case SchemaType.Boolean:
                return v => v is "true" or "false" ? null : "must be a boolean";
            case SchemaType.Url:
                return v => v.StartsWith("http://", StringComparison.Ordinal) ||
                            v.StartsWith("https://", StringComparison.Ordinal)
                    ? null
                    : "must be a valid URL";
            case SchemaType.Json:
                return v =>
                {
                    try
                    {
                        JsonDocument.Parse(v);
                        return null;
                    }
                    catch (JsonException)
                    {
                        return "must be valid JSON";
                    }
                };
            case SchemaType.Regex:
            {
                if (schema.Regex is not { } regexStr)
                    return null;
                Regex re;
                try
                {
                    re = new Regex(regexStr);
                }
                catch (ArgumentException)
                {
                    return null;
                }
                return v => re.IsMatch(v) ? null : $"must match {regexStr}";
            }
            case SchemaType.String:
            case SchemaType.Enum:
            case null:
                return _ => null;
            default:
                return _ => null;
        }
    }

    private static string? ValidateValue(string? value, VariableSchema schema)
    {
        if (value is null || value.Trim().Length == 0)
            return schema.Optional == true ? null : "value is required";

        var validator = BuildValidator(schema);
        return validator?.Invoke(value);
    }

    public List<Finding> Detect(IndexedModel index)
    {
        var schema = index.Model.Config.Schema;
        if (schema.Count == 0)
            return new List<Finding>();

        var findings = new List<Finding>();

        var entries = index.EnvDefinitions
            .OrderBy(kv => DefSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);

        foreach (var (name, defs) in entries)
        {
            if (!schema.TryGetValue(name, out var variableSchema))
                continue;

            foreach (var def in defs)
            {
                var error = ValidateValue(def.Value, variableSchema);
                if (error is null)
                    continue;
                findings.Add(MakeFinding(
                    "schema-validation",
                    Severity.Error,
                    name,
                    $"does not match schema: {error}",
                    new List<Origin> { def.Origin.Clone() }));
            }
        }

        return findings;
    }
}
