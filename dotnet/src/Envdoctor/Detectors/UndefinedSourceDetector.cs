using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Undefined-in-source: a variable referenced as `process.env.X` /
/// `import.meta.env.X` in source code that is not defined in any environment
/// file and not documented in `.env.example`. These are the most dangerous
/// findings — code that will silently read `undefined` at runtime.
public sealed class UndefinedSourceDetector : IDetector
{
    public string Id => "undefined-in-source";
    public string Name => "undefined-in-source";
    public string Description =>
        "Used in source code but not defined in any environment file and not documented in .env.example.";

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();
        var defined = index.EnvDefinitions.Keys.ToHashSet();

        var entries = index.SourceUsages
            .OrderBy(kv => OriginSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);

        foreach (var (name, origins) in entries)
        {
            if (defined.Contains(name))
                continue;
            findings.Add(MakeFinding(
                "undefined-in-source",
                Severity.Error,
                name,
                "used in source code but not defined in any environment file",
                origins.Select(o => o.Clone()).ToList()));
        }

        return findings;
    }
}
