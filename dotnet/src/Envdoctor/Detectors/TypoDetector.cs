using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Typo detector: pairs names that are referenced but not defined with names
/// that are defined but not referenced, and have a small edit distance.
public sealed class TypoDetector : IDetector
{
    public string Id => "typo";
    public string Name => "typo";
    public string Description =>
        "A referenced variable name is very similar to a defined variable name and may be a typo.";

    private static int Levenshtein(string a, string b)
    {
        var matrix = new int[b.Length + 1, a.Length + 1];
        for (var i = 0; i <= b.Length; i++)
            matrix[i, 0] = i;
        for (var j = 0; j <= a.Length; j++)
            matrix[0, j] = j;

        for (var i = 1; i <= b.Length; i++)
        {
            for (var j = 1; j <= a.Length; j++)
            {
                var cost = b[i - 1] == a[j - 1] ? 0 : 1;
                matrix[i, j] = Math.Min(
                    Math.Min(matrix[i - 1, j] + 1, matrix[i, j - 1] + 1),
                    matrix[i - 1, j - 1] + cost);
            }
        }
        return matrix[b.Length, a.Length];
    }

    /// Earliest (file, line) a name is referenced at, across usages and
    /// compose/action definitions.
    private static (string Path, int Line) ReferenceSortKey(IndexedModel index, string name)
    {
        var origins = new List<Origin>();
        if (index.Usages.TryGetValue(name, out var u))
            origins.AddRange(u);
        if (index.ComposeDefinitions.TryGetValue(name, out var cd))
            origins.AddRange(cd.Select(d => d.Origin));
        if (index.ActionDefinitions.TryGetValue(name, out var ad))
            origins.AddRange(ad.Select(d => d.Origin));
        return OriginSortKey(origins);
    }

    private static bool IsLikelyTypo(string a, string b)
    {
        if (a == b)
            return false;
        if (a.Length < 4 || b.Length < 4)
            return false;
        var distance = Levenshtein(a, b);
        var minLen = Math.Min(a.Length, b.Length);
        // Distance of 1 is always flagged for names >= 4 chars.
        // Distance of 2 is flagged for names >= 6 chars.
        // Larger distances only when names are long and ratio is low.
        if (distance == 1)
            return true;
        if (distance == 2)
            return minLen >= 6;
        if (distance == 3)
            return minLen >= 10;
        return false;
    }

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();

        var defined = index.EnvDefinitions.Keys.ToHashSet();
        var used = new HashSet<string>(index.Usages.Keys);
        used.UnionWith(index.ComposeDefinitions.Keys);
        used.UnionWith(index.ActionDefinitions.Keys);

        // Names referenced but not defined anywhere, ordered by where they are
        // first referenced (usages, then compose/action defs).
        var undefinedNames = used.Where(n => !defined.Contains(n)).ToList();
        undefinedNames.Sort((a, b) =>
        {
            var cmp = CompareKeys(ReferenceSortKey(index, a), ReferenceSortKey(index, b));
            return cmp != 0 ? cmp : string.CompareOrdinal(a, b);
        });
        // Names defined but never referenced anywhere, ordered by parse order.
        var unusedNames = index.EnvDefinitions.Keys.Where(n => !used.Contains(n)).ToList();
        unusedNames.Sort((a, b) =>
        {
            var ka = index.EnvDefinitions.TryGetValue(a, out var da) ? DefSortKey(da) : default;
            var kb = index.EnvDefinitions.TryGetValue(b, out var db) ? DefSortKey(db) : default;
            var cmp = CompareKeys(ka, kb);
            return cmp != 0 ? cmp : string.CompareOrdinal(a, b);
        });

        var seen = new HashSet<string>();

        foreach (var undefinedName in undefinedNames)
        {
            foreach (var unusedName in unusedNames)
            {
                if (!IsLikelyTypo(undefinedName, unusedName))
                    continue;
                var pairNames = new[] { undefinedName, unusedName };
                Array.Sort(pairNames, StringComparer.Ordinal);
                var pairKey = string.Join("\0", pairNames);
                if (seen.Add(pairKey))
                {
                    var origins = index.Usages.TryGetValue(undefinedName, out var o)
                        ? o.Select(x => x.Clone()).Take(3).ToList()
                        : new List<Origin>();
                    findings.Add(MakeFinding(
                        "typo",
                        Severity.Warning,
                        undefinedName,
                        $"did you mean \"{unusedName}\"? ({undefinedName} is referenced but not defined, {unusedName} is defined but unused)",
                        origins));
                }
            }
        }

        return findings;
    }
}
