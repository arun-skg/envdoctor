namespace Envdoctor.Models;

public enum FileFormat
{
    Dotenv,
    DockerCompose,
    GithubActions,
    Kubernetes,
    Source,
}

/// The parsed contents of a single file, normalized to envdoctor's model.
public sealed class EnvironmentFile
{
    public required string FilePath { get; set; }
    public FileFormat Format { get; set; }
    public string? Environment { get; set; }
    public List<EnvironmentVariable> Variables { get; set; } = new();
    public List<EnvironmentVariable> Usages { get; set; } = new();

    public EnvironmentFile Clone() =>
        new()
        {
            FilePath = FilePath,
            Format = Format,
            Environment = Environment,
            Variables = Variables.Select(v => v.Clone()).ToList(),
            Usages = Usages.Select(v => v.Clone()).ToList(),
        };

    /// Names defined in a file, deduplicated, in first-seen order.
    public List<string> DefinedNames()
    {
        var seen = new HashSet<string>();
        var result = new List<string>();
        foreach (var v in Variables)
        {
            if (seen.Add(v.Name))
                result.Add(v.Name);
        }
        return result;
    }

    /// Names used in a file, deduplicated, in first-seen order.
    public List<string> UsedNames()
    {
        var seen = new HashSet<string>();
        var result = new List<string>();
        foreach (var v in Usages)
        {
            if (seen.Add(v.Name))
                result.Add(v.Name);
        }
        return result;
    }
}
