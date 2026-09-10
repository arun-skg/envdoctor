using System.Text.RegularExpressions;

namespace Envdoctor.Models;

/// A normalized view of one environment variable across every file in the
/// project. `value` is only ever set for definitions and is never rendered in
/// CLI output or written into generated files.
public sealed class EnvironmentVariable
{
    private static readonly Regex SecretNameRe = new(
        @"(SECRET|TOKEN|PASSWORD|PASS|API[_A-Z]*KEY|PRIVATE[_-]?KEY|CREDENTIALS)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public required string Name { get; set; }
    public string? Value { get; set; }
    public bool IsSecret { get; set; }
    public VariableType VarType { get; set; }
    public List<Origin> Origins { get; set; } = new();
    public List<string>? IgnoreRules { get; set; }

    public static bool IsSecretName(string name) => SecretNameRe.IsMatch(name);

    public static EnvironmentVariable Create(
        string name,
        string? value,
        List<Origin> origins,
        List<string>? ignoreRules = null) =>
        new()
        {
            Name = name,
            Value = value,
            IsSecret = IsSecretName(name),
            VarType = Utils.TypeInfer.InferType(value),
            Origins = origins,
            IgnoreRules = ignoreRules,
        };

    public EnvironmentVariable Clone() =>
        new()
        {
            Name = Name,
            Value = Value,
            IsSecret = IsSecret,
            VarType = VarType,
            Origins = Origins.Select(o => o.Clone()).ToList(),
            IgnoreRules = IgnoreRules is null ? null : new List<string>(IgnoreRules),
        };

    /// Merge multiple variables with the same name into one, preserving every
    /// origin and preferring the first non-empty value.
    public static List<EnvironmentVariable> Merge(List<EnvironmentVariable> variables)
    {
        var byName = new Dictionary<string, EnvironmentVariable>();
        foreach (var v in variables)
        {
            if (byName.TryGetValue(v.Name, out var existing))
            {
                existing.Origins.AddRange(v.Origins);
                if (existing.Value is null && v.Value is not null)
                {
                    existing.Value = v.Value;
                    existing.VarType = Utils.TypeInfer.InferType(v.Value);
                    existing.IsSecret = IsSecretName(v.Name);
                }
            }
            else
            {
                byName[v.Name] = v;
            }
        }
        return byName.Values.ToList();
    }
}
