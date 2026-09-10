using Envdoctor.Models;
using Envdoctor.Utils;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

public sealed class EnvDiffEntry
{
    public required string Name { get; set; }
    public bool PresentInBoth { get; set; }
    public bool PresentInA { get; set; }
    public bool PresentInB { get; set; }
}

/// Environment-diff: a variable exists in one environment file but is missing
/// from another.
public sealed class EnvironmentDiffDetector : IDetector
{
    public string Id => "environment-diff";
    public string Name => "environment-diff";
    public string Description => "A variable exists in one environment file but is missing from another.";

    /// The set of variable names defined for a given environment label.
    public static HashSet<string> VariablesForEnvironment(ProjectModel model, string label)
    {
        var names = new HashSet<string>();
        foreach (var file in model.EnvFiles)
        {
            if (file.Environment == label)
            {
                foreach (var v in file.Variables)
                    names.Add(v.Name);
            }
        }
        return names;
    }

    /// Compare two environment labels, returning one entry per variable.
    public static List<EnvDiffEntry> CompareEnvironments(ProjectModel model, string labelA, string labelB)
    {
        var a = VariablesForEnvironment(model, labelA);
        var b = VariablesForEnvironment(model, labelB);
        var all = new SortedSet<string>(StringComparer.Ordinal);
        all.UnionWith(a);
        all.UnionWith(b);

        var entries = all
            .Select(name => new EnvDiffEntry
            {
                Name = name,
                PresentInA = a.Contains(name),
                PresentInB = b.Contains(name),
                PresentInBoth = a.Contains(name) && b.Contains(name),
            })
            .ToList();
        // Match the TS reference, which orders by `localeCompare`, not byte order.
        entries.Sort((x, y) => Locale.LocaleCompare(x.Name, y.Name));
        return entries;
    }

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();
        var labels = index.EnvLabels;
        if (labels.Count < 2)
            return findings;
        var reference = labels.Contains("development") ? "development" : labels[0];

        foreach (var other in labels)
        {
            if (other == reference)
                continue;
            foreach (var entry in CompareEnvironments(index.Model, reference, other))
            {
                if (entry.PresentInBoth)
                    continue;
                var missingIn = entry.PresentInA ? other : reference;
                findings.Add(MakeFinding(
                    "environment-diff",
                    Severity.Warning,
                    entry.Name,
                    $"{reference} → {other} · {entry.Name} missing in {missingIn}",
                    new List<Origin>()));
            }
        }

        return findings;
    }
}
