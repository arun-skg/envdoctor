using Envdoctor.Models;

namespace Envdoctor.Detectors;

/// The format-agnostic view detectors operate on. Built once so detectors
/// never scan raw files and never repeat the same work.
public sealed class IndexedModel
{
    public required ProjectModel Model { get; init; }
    /// Every definition found in dotenv files, keyed by name (duplicates kept).
    public Dictionary<string, List<Definition>> EnvDefinitions { get; init; } = new();
    public Dictionary<string, List<Definition>> ComposeDefinitions { get; init; } = new();
    public Dictionary<string, List<Definition>> ActionDefinitions { get; init; } = new();
    public Dictionary<string, List<Definition>> K8sDefinitions { get; init; } = new();
    /// Every usage (source, compose, actions, k8s), keyed by name.
    public Dictionary<string, List<Origin>> Usages { get; init; } = new();
    /// Usages that come specifically from source code.
    public Dictionary<string, List<Origin>> SourceUsages { get; init; } = new();
    /// Names documented in `.env.example`.
    public HashSet<string> ExampleNames { get; init; } = new();
    /// Distinct environment labels among dotenv files (excluding "example").
    public List<string> EnvLabels { get; init; } = new();

    public static IndexedModel BuildIndex(ProjectModel model)
    {
        var envDefinitions = new Dictionary<string, List<Definition>>();
        var composeDefinitions = new Dictionary<string, List<Definition>>();
        var actionDefinitions = new Dictionary<string, List<Definition>>();
        var k8sDefinitions = new Dictionary<string, List<Definition>>();
        var usages = new Dictionary<string, List<Origin>>();
        var sourceUsages = new Dictionary<string, List<Origin>>();
        var exampleNames = new HashSet<string>();
        var envLabels = new List<string>();

        static void PushDef(Dictionary<string, List<Definition>> map, Definition def)
        {
            if (!map.TryGetValue(def.Name, out var list))
                map[def.Name] = list = new List<Definition>();
            list.Add(def);
        }

        static void PushOrigin(Dictionary<string, List<Origin>> map, string name, Origin origin)
        {
            if (!map.TryGetValue(name, out var list))
                map[name] = list = new List<Origin>();
            list.Add(origin);
        }

        // Process env files
        foreach (var file in model.EnvFiles)
        {
            if (file.Environment == "example")
            {
                // .env.example documents what *should* exist but is not a
                // runtime value. Add to exampleNames only.
                foreach (var v in file.Variables)
                    exampleNames.Add(v.Name);
                continue;
            }

            if (file.Environment is not null && !envLabels.Contains(file.Environment))
                envLabels.Add(file.Environment);

            foreach (var v in file.Variables)
            {
                var def = new Definition
                {
                    Name = v.Name,
                    Value = v.Value,
                    VarType = v.VarType,
                    IsSecret = v.IsSecret,
                    Environment = file.Environment,
                    Origin = v.Origins.FirstOrDefault()?.Clone() ?? new Origin
                    {
                        FilePath = file.FilePath,
                        Kind = OriginKind.Definition,
                        Environment = file.Environment,
                        Format = OriginFormat.Dotenv,
                    },
                };
                PushDef(envDefinitions, def);
            }

            foreach (var v in file.Usages)
            {
                foreach (var origin in v.Origins)
                    PushOrigin(usages, v.Name, origin.Clone());
            }
        }

        foreach (var (files, format, map) in new (List<EnvironmentFile>, OriginFormat, Dictionary<string, List<Definition>>)[]
        {
            (model.ComposeFiles, OriginFormat.DockerCompose, composeDefinitions),
            (model.ActionFiles, OriginFormat.GithubActions, actionDefinitions),
            (model.K8sFiles, OriginFormat.Kubernetes, k8sDefinitions),
        })
        {
            foreach (var file in files)
            {
                foreach (var v in file.Variables)
                {
                    var def = new Definition
                    {
                        Name = v.Name,
                        Value = v.Value,
                        VarType = v.VarType,
                        IsSecret = v.IsSecret,
                        Origin = v.Origins.FirstOrDefault()?.Clone() ?? new Origin
                        {
                            FilePath = file.FilePath,
                            Kind = OriginKind.Definition,
                            Format = format,
                        },
                    };
                    PushDef(map, def);
                }

                foreach (var v in file.Usages)
                {
                    foreach (var origin in v.Origins)
                        PushOrigin(usages, v.Name, origin.Clone());
                }
            }
        }

        // Process source files
        foreach (var file in model.SourceFiles)
        {
            foreach (var v in file.Usages)
            {
                foreach (var origin in v.Origins)
                {
                    PushOrigin(usages, v.Name, origin.Clone());
                    PushOrigin(sourceUsages, v.Name, origin.Clone());
                }
            }
        }

        return new IndexedModel
        {
            Model = model,
            EnvDefinitions = envDefinitions,
            ComposeDefinitions = composeDefinitions,
            ActionDefinitions = actionDefinitions,
            K8sDefinitions = k8sDefinitions,
            Usages = usages,
            SourceUsages = sourceUsages,
            ExampleNames = exampleNames,
            EnvLabels = envLabels,
        };
    }
}
