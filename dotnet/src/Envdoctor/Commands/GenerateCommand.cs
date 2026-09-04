using Envdoctor.Core;
using Envdoctor.Generators;

namespace Envdoctor.Commands;

public enum GenerateTarget
{
    EnvExample,
    EnvDoc,
    EnvTypes,
    ConfigSchema,
    ConfigTemplate,
    GithubActions,
}

public sealed class GenerateArgs
{
    public GenerateTarget Target { get; set; }
    public string? Root { get; set; }
    public string? Output { get; set; }
}

public static class GenerateCommand
{
    public static int Run(GenerateArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        var (model, config) = Pipeline.LoadProject(root);

        var output = args.Target switch
        {
            GenerateTarget.EnvExample => EnvExampleGenerator.GenerateEnvExample(model, config),
            GenerateTarget.EnvDoc => EnvironmentDocGenerator.GenerateEnvironmentDoc(model, config),
            GenerateTarget.EnvTypes => EnvTypesGenerator.GenerateEnvTypes(model, config),
            GenerateTarget.ConfigSchema => SchemaGenerator.GenerateConfigSchema(),
            GenerateTarget.ConfigTemplate => SchemaGenerator.GenerateConfigTemplate(),
            GenerateTarget.GithubActions => GithubActionsGenerator.GenerateGithubActions(model, config),
            _ => throw new ArgumentOutOfRangeException(nameof(args)),
        };

        if (args.Output is { } path)
        {
            File.WriteAllText(path, output);
            Console.Out.WriteLine($"Written to {path}");
        }
        else
        {
            Console.Out.WriteLine(output);
        }

        return 0;
    }
}
