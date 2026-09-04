using Envdoctor.Generators;

namespace Envdoctor.Commands;

public sealed class InitArgs
{
    public string? Root { get; set; }
    public bool Force { get; set; }
}

public static class InitCommand
{
    public static int Run(InitArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        var configPath = Path.Combine(root, "envdoctor.config.toml");

        if (File.Exists(configPath) && !args.Force)
        {
            Console.Error.WriteLine($"Config already exists at {configPath}. Use --force to overwrite.");
            return 1;
        }

        var template = SchemaGenerator.GenerateConfigTemplate();
        File.WriteAllText(configPath, template);

        Console.Out.WriteLine($"Created {configPath}");
        Console.Out.WriteLine("Edit the file to customize your configuration, then run `envdoctor scan`.");

        return 0;
    }
}
