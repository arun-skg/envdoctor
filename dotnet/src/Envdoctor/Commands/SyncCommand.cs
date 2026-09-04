using Envdoctor.Config;
using Envdoctor.Core;
using Envdoctor.Models;

namespace Envdoctor.Commands;

public sealed class SyncArgs
{
    public string? Root { get; set; }
    public string From { get; set; } = "";
    public string To { get; set; } = "";
    public bool DryRun { get; set; }
}

public static class SyncCommand
{
    /// `envdoctor sync <from> <to>` — copy missing variable keys from one
    /// environment file to another, using placeholder values. Never copies
    /// real secret values.
    public static int Run(SyncArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        var fromLabel = Shared.NormalizeEnvLabel(args.From);
        var toLabel = Shared.NormalizeEnvLabel(args.To);

        var (model, config) = Pipeline.LoadProject(root);

        var fromNames = NamesForEnvironment(model, fromLabel);
        var toNames = NamesForEnvironment(model, toLabel);

        var missing = fromNames.Where(n => !toNames.Contains(n)).ToList();

        if (missing.Count == 0)
        {
            Console.Out.WriteLine($"✓ {fromLabel} → {toLabel}: nothing to sync");
            return 0;
        }

        var targetFile = TargetEnvPath(root, toLabel, config);
        var targetRel = Discover.RelativeTo(root, targetFile) ?? targetFile;

        var lines = new List<string> { "", $"# Synced from {fromLabel} by envdoctor" };
        foreach (var name in missing)
        {
            var placeholder = EnvironmentVariable.IsSecretName(name) ? "" : $"your_{name.ToLowerInvariant()}";
            lines.Add($"{name}={placeholder}");
        }
        var append = string.Join("\n", lines) + "\n";

        if (args.DryRun)
        {
            Console.Out.WriteLine("envdoctor sync (dry run)\n");
            Console.Out.WriteLine($"Would append {missing.Count} key{Plural(missing.Count)} to {targetRel}:");
            foreach (var name in missing)
                Console.Out.WriteLine($"  + {name}");
            return 0;
        }

        var parentDir = Path.GetDirectoryName(targetFile);
        if (!string.IsNullOrEmpty(parentDir))
            Directory.CreateDirectory(parentDir);
        File.AppendAllText(targetFile, append);

        Console.Out.WriteLine("envdoctor sync\n");
        Console.Out.WriteLine($"  ✓ Appended {missing.Count} key{Plural(missing.Count)} to {targetRel}");
        foreach (var name in missing)
            Console.Out.WriteLine($"    + {name}");

        return 0;
    }

    /// Sorted set of variable names defined for an environment label.
    private static SortedSet<string> NamesForEnvironment(ProjectModel model, string label)
    {
        var names = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var file in model.EnvFiles)
        {
            if (file.Environment == label)
            {
                foreach (var v in file.Variables)
                    names.Add(v.Name);
            }
        }
        return names;
    }

    /// Resolve the file that should receive synced keys for a target label.
    private static string TargetEnvPath(string root, string label, EnvdoctorConfig config)
    {
        if (config.Environments is not null &&
            config.Environments.TryGetValue(label, out var files) &&
            files.Count > 0)
        {
            return Path.Combine(root, files[0]);
        }
        return label == "development"
            ? Path.Combine(root, ".env")
            : Path.Combine(root, $".env.{label}");
    }

    private static string Plural(int n) => n == 1 ? "" : "s";
}
