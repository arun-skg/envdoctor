using Envdoctor.Core;
using Envdoctor.Detectors;
using Envdoctor.Utils;

namespace Envdoctor.Commands;

public sealed class DiffArgs
{
    public string? Root { get; set; }
    public string EnvA { get; set; } = "";
    public string EnvB { get; set; } = "";
    public bool Json { get; set; }
}

public static class DiffCommand
{
    /// `envdoctor diff <env1> <env2>` — compare variable sets across environments.
    public static int Run(DiffArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        var (model, _) = Pipeline.LoadProject(root);
        var labelA = Shared.NormalizeEnvLabel(args.EnvA);
        var labelB = Shared.NormalizeEnvLabel(args.EnvB);

        var available = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var f in model.EnvFiles)
        {
            if (f.Environment is not null && f.Environment != "example")
                available.Add(f.Environment);
        }

        Shared.ReportParseErrors(model, root);

        if (!available.Contains(labelA) || !available.Contains(labelB))
        {
            if (!available.Contains(labelA))
                Console.Error.WriteLine($"error Environment \"{labelA}\" has no files in this project.");
            if (!available.Contains(labelB))
                Console.Error.WriteLine($"error Environment \"{labelB}\" has no files in this project.");
            Console.Error.WriteLine($"  Available: {(available.Count == 0 ? "none" : string.Join(", ", available))}");
            return 2;
        }

        var entries = EnvironmentDiffDetector.CompareEnvironments(model, labelA, labelB);
        var missingCount = entries.Count(e => !e.PresentInBoth);

        if (args.Json)
        {
            var variables = entries.Select(e => (object)new JsonObject
            {
                { "name", e.Name },
                { "status", e.PresentInBoth ? "same" : "missing" },
                { "missingIn", e.PresentInBoth ? null : e.PresentInA ? labelB : labelA },
            }).ToList();
            Console.Out.WriteLine(Json.Pretty(new JsonObject
            {
                { "environments", new List<object?> { labelA, labelB } },
                { "exitCode", missingCount > 0 ? 1 : 0 },
                { "total", entries.Count },
                { "missing", missingCount },
                { "variables", variables },
            }));
            return missingCount > 0 ? 1 : 0;
        }

        const string title = "ENVIRONMENT DIFF";
        Console.Out.WriteLine(title);
        Console.Out.WriteLine(new string('─', title.Length * 2) + "\n");
        Console.Out.WriteLine($"  {labelA} → {labelB}\n");

        foreach (var entry in entries)
        {
            if (entry.PresentInBoth)
                Console.Out.WriteLine($"  ✓ {entry.Name}  present in both");
            else if (entry.PresentInA)
                Console.Out.WriteLine($"  ❌ {entry.Name}  missing in {labelB}");
            else
                Console.Out.WriteLine($"  ❌ {entry.Name}  missing in {labelA}");
        }
        Console.Out.WriteLine(
            $"\n  Summary: {entries.Count} variables · {missingCount} missing · {entries.Count - missingCount} present in both");

        return missingCount > 0 ? 1 : 0;
    }
}
