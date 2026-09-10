namespace Envdoctor.Models;

public enum OriginKind
{
    Definition,
    Reference,
    Usage,
}

public static class OriginKindExtensions
{
    public static string AsStr(this OriginKind k) => k switch
    {
        OriginKind.Definition => "definition",
        OriginKind.Reference => "reference",
        OriginKind.Usage => "usage",
        _ => "usage",
    };
}

public enum OriginFormat
{
    Dotenv,
    DockerCompose,
    GithubActions,
    Kubernetes,
    Source,
}

public static class OriginFormatExtensions
{
    public static string AsStr(this OriginFormat f) => f switch
    {
        OriginFormat.Dotenv => "dotenv",
        OriginFormat.DockerCompose => "docker-compose",
        OriginFormat.GithubActions => "github-actions",
        OriginFormat.Kubernetes => "kubernetes",
        OriginFormat.Source => "source",
        _ => "source",
    };
}

/// Where a variable name was seen, and in what role. Values are intentionally
/// NOT carried here.
public sealed class Origin
{
    public required string FilePath { get; set; }
    public int? Line { get; set; }
    public OriginKind Kind { get; set; }
    public string? Environment { get; set; }
    public OriginFormat? Format { get; set; }
    public string? Subkind { get; set; }

    public Origin Clone() => (Origin)MemberwiseClone();

    public static Origin NewDefinition(string filePath, int? line, string? environment) =>
        new()
        {
            FilePath = filePath,
            Line = line,
            Kind = OriginKind.Definition,
            Environment = environment,
            Format = OriginFormat.Dotenv,
        };

    public static Origin NewReference(string filePath, int? line, string? environment) =>
        new()
        {
            FilePath = filePath,
            Line = line,
            Kind = OriginKind.Reference,
            Environment = environment,
            Format = OriginFormat.Dotenv,
        };

    public static Origin NewUsage(string filePath, int? line, OriginFormat format) =>
        new()
        {
            FilePath = filePath,
            Line = line,
            Kind = OriginKind.Usage,
            Format = format,
        };

    public Origin WithSubkind(string subkind)
    {
        Subkind = subkind;
        return this;
    }
}
