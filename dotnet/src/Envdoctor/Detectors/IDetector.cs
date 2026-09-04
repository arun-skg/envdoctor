using Envdoctor.Models;

namespace Envdoctor.Detectors;

/// A concrete definition of a variable in one file.
public sealed class Definition
{
    public required string Name { get; set; }
    public string? Value { get; set; }
    public VariableType VarType { get; set; }
    public bool IsSecret { get; set; }
    public string? Environment { get; set; }
    public required Origin Origin { get; set; }
}

public interface IDetector
{
    string Id { get; }
    string Name { get; }
    string Description { get; }
    List<Finding> Detect(IndexedModel index);
}

public static class DetectorHelpers
{
    public static Finding MakeFinding(
        string ruleId,
        Severity severity,
        string variable,
        string message,
        List<Origin> locations) =>
        Finding.New(ruleId, severity, variable, message, locations);

    private static (string Path, int Line) OriginKey(Origin o) => (o.FilePath, o.Line ?? int.MaxValue);

    /// Stable ordering key for a set of definitions: the earliest (file, line)
    /// they were declared at. Matches the reference CLI's parse-order emission.
    public static (string Path, int Line) DefSortKey(List<Definition> defs) =>
        defs.Count == 0 ? default : defs.Select(d => OriginKey(d.Origin)).Min();

    /// Stable ordering key for a set of origins: the earliest (file, line).
    public static (string Path, int Line) OriginSortKey(List<Origin> origins) =>
        origins.Count == 0 ? default : origins.Select(OriginKey).Min();

    public static int CompareKeys((string Path, int Line) a, (string Path, int Line) b)
    {
        var cmp = string.CompareOrdinal(a.Path, b.Path);
        return cmp != 0 ? cmp : a.Line.CompareTo(b.Line);
    }
}
