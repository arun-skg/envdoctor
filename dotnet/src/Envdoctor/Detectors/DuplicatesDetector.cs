using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Duplicates: the same variable defined more than once within a single file.
/// dotenv applies last-wins, so a repeated key is a silent override that
/// usually means a merge conflict or a copy-paste bug.
public sealed class DuplicatesDetector : IDetector
{
    public string Id => "duplicates";
    public string Name => "duplicates";
    public string Description => "The same variable is defined more than once in a single file.";

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();

        foreach (var file in index.Model.EnvFiles)
        {
            var byName = new Dictionary<string, List<Origin>>();
            // Track first-seen order so output matches the reference CLI.
            var order = new List<string>();
            foreach (var v in file.Variables)
            {
                if (!byName.ContainsKey(v.Name))
                    order.Add(v.Name);
                if (!byName.TryGetValue(v.Name, out var entry))
                    byName[v.Name] = entry = new List<Origin>();
                entry.AddRange(v.Origins.Select(o => o.Clone()));
            }

            foreach (var name in order)
            {
                var origins = byName[name];
                if (origins.Count < 2)
                    continue;
                var lines = origins.Where(o => o.Line is not null).Select(o => o.Line!.Value).ToList();
                var whereStr = lines.Count > 0
                    ? $"on lines {string.Join(", ", lines)}"
                    : "in this file";
                findings.Add(MakeFinding(
                    "duplicates",
                    Severity.Error,
                    name,
                    $"defined {origins.Count} times {whereStr}",
                    origins));
            }
        }

        return findings;
    }
}
