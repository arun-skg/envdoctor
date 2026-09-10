using Envdoctor.Models;
using static Envdoctor.Detectors.DetectorHelpers;

namespace Envdoctor.Detectors;

/// Type mismatch: the same variable is defined with values of incompatible
/// inferred types across environment files. The "expected" type is taken from
/// the development file when present, otherwise the most common type. Only
/// variable *types* and locations are reported — never values.
public sealed class TypeMismatchDetector : IDetector
{
    public string Id => "type-mismatch";
    public string Name => "type-mismatch";
    public string Description => "The same variable has incompatible inferred types across environment files.";

    public List<Finding> Detect(IndexedModel index)
    {
        var findings = new List<Finding>();

        var entries = index.EnvDefinitions
            .OrderBy(kv => DefSortKey(kv.Value), Comparer<(string Path, int Line)>.Create(CompareKeys))
            .ThenBy(kv => kv.Key, StringComparer.Ordinal);

        foreach (var (name, defs) in entries)
        {
            var typed = defs
                .Where(d => d.Value is not null && d.VarType != VariableType.Unknown && d.Value.Length > 0)
                .ToList();
            if (typed.Count < 2)
                continue;

            var distinctTypes = typed.Select(d => d.VarType).ToHashSet();
            if (distinctTypes.Count < 2)
                continue;

            var expected = typed
                .FirstOrDefault(d => d.Environment == "development")
                ?.VarType ?? MostCommonType(typed);

            foreach (var def in typed)
            {
                if (def.VarType == expected)
                    continue;
                findings.Add(MakeFinding(
                    "type-mismatch",
                    Severity.Error,
                    name,
                    $"expected: {expected.AsStr()}, found: {def.VarType.AsStr()}",
                    new List<Origin> { def.Origin.Clone() }));
            }
        }

        return findings;
    }

    private static VariableType MostCommonType(List<Definition> defs)
    {
        // Count occurrences but resolve ties by first-seen order, matching the
        // reference CLI.
        var counts = new Dictionary<VariableType, int>();
        var order = new List<VariableType>();
        foreach (var d in defs)
        {
            if (!counts.ContainsKey(d.VarType))
                order.Add(d.VarType);
            counts[d.VarType] = counts.GetValueOrDefault(d.VarType) + 1;
        }
        var best = order[0];
        var bestCount = 0;
        foreach (var ty in order)
        {
            var count = counts[ty];
            if (count > bestCount)
            {
                best = ty;
                bestCount = count;
            }
        }
        return best;
    }
}
