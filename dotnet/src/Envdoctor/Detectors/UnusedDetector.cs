using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Unused: a variable defined in an environment file that is never referenced
/// anywhere. `.env.example` contents are documentation and are excluded here.
public sealed class UnusedDetector : IDetector
{
    public string Id => "unused";
    public string Name => "unused";
    public string Description =>
        "Defined in an environment file but never referenced in source, docker-compose, GitHub Actions, or Kubernetes manifests.";

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();
        var used = new HashSet<string>(index.Usages.Keys);
        used.UnionWith(index.ComposeDefinitions.Keys);
        used.UnionWith(index.ActionDefinitions.Keys);
        used.UnionWith(index.K8sDefinitions.Keys);

        // Iterate in a stable file/line order so output is deterministic and
        // matches the reference CLI.
        var entries = index.EnvDefinitions
            .OrderBy(kv => DefSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);

        var seen = new HashSet<string>();

        foreach (var (name, defs) in entries)
        {
            if (!seen.Add(name))
                continue;
            if (used.Contains(name))
                continue;
            findings.Add(MakeFinding(
                "unused",
                Severity.Warning,
                name,
                "defined but never referenced",
                defs.Select(d => d.Origin.Clone()).ToList()));
        }

        return findings;
    }
}
