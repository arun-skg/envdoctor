using Envdoctor.Models;

namespace Envdoctor.Runtime;

/// How an item relates across two snapshots.
public enum RuntimeStatus
{
    Same,
    Different,
    OnlyA,
    OnlyB,
}

public static class RuntimeStatusExtensions
{
    public static string AsStr(this RuntimeStatus s) => s switch
    {
        RuntimeStatus.Same => "same",
        RuntimeStatus.Different => "different",
        RuntimeStatus.OnlyA => "onlyA",
        RuntimeStatus.OnlyB => "onlyB",
        _ => "same",
    };
}

public sealed class OsDiff
{
    public RuntimeStatus Status { get; set; }
    public string A { get; set; } = "";
    public string B { get; set; } = "";
}

public sealed class ToolDiff
{
    public string Name { get; set; } = "";
    public RuntimeStatus Status { get; set; }
    public string? A { get; set; }
    public string? B { get; set; }
}

public sealed class GlobalDiff
{
    public string Ecosystem { get; set; } = "";
    public string Name { get; set; } = "";
    public RuntimeStatus Status { get; set; }
    public string? A { get; set; }
    public string? B { get; set; }
}

public sealed class RuntimeDiff
{
    public OsDiff Os { get; set; } = new();
    public List<ToolDiff> Tools { get; set; } = new();
    /// True when both share the same PATH entries but in a different order.
    public bool PathReordered { get; set; }
    public List<string> PathOnlyA { get; set; } = new();
    public List<string> PathOnlyB { get; set; } = new();
    public List<GlobalDiff> Globals { get; set; } = new();
    public List<string> EnvFlagOnlyA { get; set; } = new();
    public List<string> EnvFlagOnlyB { get; set; } = new();
    /// True when nothing meaningful differs (drift-free).
    public bool Equivalent { get; set; }
}

public static class Compare
{
    private static RuntimeStatus StatusFor(string? a, string? b) => (a, b) switch
    {
        (not null, not null) => a == b ? RuntimeStatus.Same : RuntimeStatus.Different,
        (not null, null) => RuntimeStatus.OnlyA,
        _ => RuntimeStatus.OnlyB,
    };

    private static List<ToolDiff> DiffTools(RuntimeSnapshot a, RuntimeSnapshot b)
    {
        var av = a.Tools.ToDictionary(t => t.Tool, t => t.Version);
        var bv = b.Tools.ToDictionary(t => t.Tool, t => t.Version);
        var names = new SortedSet<string>(StringComparer.Ordinal);
        names.UnionWith(av.Keys);
        names.UnionWith(bv.Keys);
        return names
            .Select(name => new ToolDiff
            {
                Name = name,
                Status = StatusFor(av.GetValueOrDefault(name), bv.GetValueOrDefault(name)),
                A = av.GetValueOrDefault(name),
                B = bv.GetValueOrDefault(name),
            })
            .ToList();
    }

    private static List<GlobalDiff> DiffGlobals(RuntimeSnapshot a, RuntimeSnapshot b)
    {
        static Dictionary<string, string> Index(List<GlobalPackage>? list) =>
            list?.ToDictionary(p => p.Name, p => p.Version) ?? new Dictionary<string, string>();

        var ecosystems = new SortedSet<string>(StringComparer.Ordinal);
        ecosystems.UnionWith(a.Globals.Keys);
        ecosystems.UnionWith(b.Globals.Keys);
        var result = new List<GlobalDiff>();
        foreach (var eco in ecosystems)
        {
            var av = Index(a.Globals.GetValueOrDefault(eco));
            var bv = Index(b.Globals.GetValueOrDefault(eco));
            var names = new SortedSet<string>(StringComparer.Ordinal);
            names.UnionWith(av.Keys);
            names.UnionWith(bv.Keys);
            foreach (var name in names)
            {
                var status = StatusFor(av.GetValueOrDefault(name), bv.GetValueOrDefault(name));
                if (status == RuntimeStatus.Same)
                    continue;
                result.Add(new GlobalDiff
                {
                    Ecosystem = eco,
                    Name = name,
                    Status = status,
                    A = av.GetValueOrDefault(name),
                    B = bv.GetValueOrDefault(name),
                });
            }
        }
        result.Sort((x, y) => string.CompareOrdinal(x.Name, y.Name));
        return result;
    }

    /// Set difference preserving A's order.
    private static List<string> OnlyIn(List<string> a, List<string> b)
    {
        var set = b.ToHashSet();
        return a.Where(x => !set.Contains(x)).ToList();
    }

    /// Pure comparison of two runtime snapshots. `capturedAt` is ignored.
    public static RuntimeDiff CompareSnapshots(RuntimeSnapshot a, RuntimeSnapshot b)
    {
        var tools = DiffTools(a, b);
        var pathOnlyA = OnlyIn(a.Path, b.Path);
        var pathOnlyB = OnlyIn(b.Path, a.Path);
        var pathReordered = pathOnlyA.Count == 0 && pathOnlyB.Count == 0 &&
            string.Join("\0", a.Path) != string.Join("\0", b.Path);
        var globals = DiffGlobals(a, b);
        var envFlagOnlyA = OnlyIn(a.EnvFlagNames, b.EnvFlagNames);
        var envFlagOnlyB = OnlyIn(b.EnvFlagNames, a.EnvFlagNames);

        var osSame = a.Os.Platform == b.Os.Platform && a.Os.Arch == b.Os.Arch && a.Os.Release == b.Os.Release;
        string FmtOs(RuntimeSnapshot s) => $"{s.Os.Platform}/{s.Os.Arch} {s.Os.Release}";

        var equivalent = tools.All(t => t.Status == RuntimeStatus.Same) &&
            !pathReordered &&
            pathOnlyA.Count == 0 &&
            pathOnlyB.Count == 0 &&
            globals.Count == 0;

        return new RuntimeDiff
        {
            Os = new OsDiff
            {
                Status = osSame ? RuntimeStatus.Same : RuntimeStatus.Different,
                A = FmtOs(a),
                B = FmtOs(b),
            },
            Tools = tools,
            PathReordered = pathReordered,
            PathOnlyA = pathOnlyA,
            PathOnlyB = pathOnlyB,
            Globals = globals,
            EnvFlagOnlyA = envFlagOnlyA,
            EnvFlagOnlyB = envFlagOnlyB,
            Equivalent = equivalent,
        };
    }
}
