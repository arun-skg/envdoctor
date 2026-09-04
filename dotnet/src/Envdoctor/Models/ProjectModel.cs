using Envdoctor.Config;

namespace Envdoctor.Models;

/// The fully assembled, format-agnostic view of a project.
public sealed class ProjectModel
{
    public required string RootDir { get; set; }
    public EnvdoctorConfig Config { get; set; } = new();
    public List<EnvironmentFile> EnvFiles { get; set; } = new();
    public List<EnvironmentFile> ComposeFiles { get; set; } = new();
    public List<EnvironmentFile> ActionFiles { get; set; } = new();
    public List<EnvironmentFile> K8sFiles { get; set; } = new();
    public List<EnvironmentFile> SourceFiles { get; set; } = new();
    public List<EnvironmentFile> AllFiles { get; set; } = new();
    public List<ParseError> ParseErrors { get; set; } = new();

    /// All definitions (variables with values) across the whole project.
    public IEnumerable<EnvironmentVariable> AllDefinitions() =>
        EnvFiles.SelectMany(f => f.Variables)
            .Concat(ComposeFiles.SelectMany(f => f.Variables))
            .Concat(ActionFiles.SelectMany(f => f.Variables));

    /// All usages (name references without values) across the whole project.
    public IEnumerable<EnvironmentVariable> AllUsages() =>
        EnvFiles.SelectMany(f => f.Usages)
            .Concat(ComposeFiles.SelectMany(f => f.Usages))
            .Concat(ActionFiles.SelectMany(f => f.Usages))
            .Concat(SourceFiles.SelectMany(f => f.Usages));

    /// Flatten every origin for a name into a deduplicated list.
    public List<Origin> OriginsForName(string name)
    {
        var seen = new Dictionary<string, Origin>();
        foreach (var file in AllFiles)
        {
            foreach (var v in file.Variables.Concat(file.Usages))
            {
                if (v.Name != name)
                    continue;
                foreach (var origin in v.Origins)
                {
                    var key = $"{origin.FilePath}:{origin.Line}:{origin.Kind}";
                    if (!seen.ContainsKey(key))
                        seen[key] = origin.Clone();
                }
            }
        }
        return seen.Values.ToList();
    }
}

public sealed class ParseError
{
    public required string FilePath { get; set; }
    public required string Error { get; set; }
}
