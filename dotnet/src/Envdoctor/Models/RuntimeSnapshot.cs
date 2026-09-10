namespace Envdoctor.Models;

/// Schema version for the runtime snapshot format.
public static class SnapshotSchema
{
    public const string Value = "envdoctor.runtime-snapshot.v1";
}

public sealed class RuntimeSnapshot
{
    public string Schema { get; set; } = SnapshotSchema.Value;
    public string CapturedAt { get; set; } = "";
    public OsInfo Os { get; set; } = new();
    public List<ToolInfo> Tools { get; set; } = new();
    public List<string> Path { get; set; } = new();
    public Dictionary<string, List<GlobalPackage>> Globals { get; set; } = new();
    public List<string> EnvFlagNames { get; set; } = new();
}

public sealed class OsInfo
{
    public string Platform { get; set; } = "";
    public string Arch { get; set; } = "";
    public string Release { get; set; } = "";
}

public sealed class ToolInfo
{
    public string Tool { get; set; } = "";
    public string Version { get; set; } = "";
    public string ResolvedFrom { get; set; } = "";
}

public sealed class GlobalPackage
{
    public string Name { get; set; } = "";
    public string Version { get; set; } = "";
}
