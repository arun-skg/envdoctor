using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Weak/placeholder secret detector. Only inspects definitions in actual
/// environment files, never `.env.example`.
public sealed class WeakSecretDetector : IDetector
{
    private static readonly HashSet<string> Blocklist = new(StringComparer.Ordinal)
    {
        "",
        "changeme",
        "password",
        "password123",
        "secret",
        "secret123",
        "token",
        "key",
        "apikey",
        "api_key",
        "test",
        "testing",
        "12345678",
        "123456789",
        "your_secret",
        "your_token",
        "your_api_key",
        "your_password",
        "example",
        "dummy",
        "foo",
        "bar",
        "admin",
        "default",
        "null",
        "undefined",
    };

    public string Id => "weak-secret";
    public string Name => "weak-secret";
    public string Description => "A secret-looking variable in an environment file has a weak or placeholder value.";

    private static bool IsWeakSecret(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
            return false;
        if (Blocklist.Contains(trimmed.ToLowerInvariant()))
            return true;
        return trimmed.Length < 8;
    }

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();

        var entries = index.EnvDefinitions
            .OrderBy(kv => DefSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);

        foreach (var (name, defs) in entries)
        {
            foreach (var def in defs)
            {
                if (!def.IsSecret)
                    continue;
                if (def.Value is null || !IsWeakSecret(def.Value))
                    continue;
                var location = def.Origin.Line is { } line
                    ? $"{def.Origin.FilePath}:{line}"
                    : def.Origin.FilePath;
                findings.Add(MakeFinding(
                    "weak-secret",
                    Severity.Warning,
                    name,
                    $"{name} has a weak or placeholder value in {location}",
                    new List<Origin> { def.Origin.Clone() }));
            }
        }

        return findings;
    }
}
