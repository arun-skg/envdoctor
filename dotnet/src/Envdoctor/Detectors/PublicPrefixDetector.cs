using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Public-prefix leak: variables whose names match the secret heuristic but
/// use a framework prefix that exposes them to client-side bundles.
public sealed class PublicPrefixDetector : IDetector
{
    private static readonly string[] PublicPrefixes =
    {
        "NEXT_PUBLIC_",
        "VITE_",
        "PUBLIC_",
        "REACT_APP_",
        "GATSBY_",
        "EXPO_PUBLIC_",
        "NUXT_PUBLIC_",
        "ASTRO_PUBLIC_",
    };

    public string Id => "public-prefix";
    public string Name => "public-prefix";
    public string Description =>
        "A secret-looking variable uses a public framework prefix and will be exposed to client bundles.";

    private static string? FindPublicPrefix(string name) =>
        PublicPrefixes.FirstOrDefault(name.StartsWith);

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();

        var entries = index.EnvDefinitions
            .OrderBy(kv => DefSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);

        foreach (var (name, defs) in entries)
        {
            var prefix = FindPublicPrefix(name);
            if (prefix is null)
                continue;
            if (!EnvironmentVariable.IsSecretName(name))
                continue;
            findings.Add(MakeFinding(
                "public-prefix",
                Severity.Error,
                name,
                $"{name} uses public prefix \"{prefix}\"; secret-looking variables with this prefix are exposed to client bundles",
                defs.Select(d => d.Origin.Clone()).ToList()));
        }

        return findings;
    }
}
