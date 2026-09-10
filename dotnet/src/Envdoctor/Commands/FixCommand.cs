using Envdoctor.Core;
using Envdoctor.Detectors;
using Envdoctor.Generators;
using Envdoctor.Models;

namespace Envdoctor.Commands;

public sealed class FixArgs
{
    public string? Root { get; set; }
    public bool DryRun { get; set; }
    public bool Force { get; set; }
}

public static class FixCommand
{
    private enum Action
    {
        Create,
        Update,
        Skip,
    }

    private sealed record PlannedFile(string RelPath, Action ActionKind, string Content);

    /// `envdoctor fix` — run the audit, then regenerate the safe, generated
    /// artifacts: `.env.example`, `ENVIRONMENT.md`, `env.d.ts`,
    /// `envdoctor.schema.ts`, and (when the project uses GitHub Actions
    /// secrets/vars) `.github/ENVIRONMENT.md`. Never touches real `.env` files
    /// and never writes secret values. `--dry-run` previews changes.
    public static int Run(FixArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        var (model, config) = Pipeline.LoadProject(root);
        var index = IndexedModel.BuildIndex(model);
        var findings = Audit.RunAudit(model, config, index);
        var exitCode = ExitCodes.AuditExitCode(new ExitContext { Findings = findings, Strict = false });

        var checklist = GithubActionsGenerator.CollectActionsChecklist(model);
        var hasActionsRefs = checklist.Secrets.Count > 0 || checklist.Vars.Count > 0;

        var plans = new List<PlannedFile>
        {
            Plan(root, ".env.example", EnvExampleGenerator.GenerateEnvExample(model, config), args),
            Plan(root, "ENVIRONMENT.md", EnvironmentDocGenerator.GenerateEnvironmentDoc(model, config), args),
            Plan(root, "env.d.ts", EnvTypesGenerator.GenerateEnvTypes(model, config), args),
            Plan(root, "envdoctor.schema.ts", SchemaGenerator.GenerateVariableSchemaTs(model), args),
        };
        if (hasActionsRefs)
        {
            plans.Add(Plan(root, ".github/ENVIRONMENT.md", GithubActionsGenerator.GenerateActionsChecklist(model), args));
        }

        if (args.DryRun)
        {
            Console.Out.WriteLine("envdoctor fix (dry run)\n");
            foreach (var p in plans)
            {
                var marker = p.ActionKind switch
                {
                    Action.Create => "+",
                    Action.Update => "~",
                    _ => "·",
                };
                Console.Out.WriteLine($"  {marker} {p.RelPath}  {ActionLabel(p.ActionKind)}");
            }
            var pending = plans.Count(p => p.ActionKind != Action.Skip);
            Console.Out.WriteLine($"\n  {pending} change{Plural(pending)} planned");
            return exitCode;
        }

        var created = 0;
        var updated = 0;
        foreach (var p in plans)
        {
            if (p.ActionKind == Action.Skip)
                continue;
            var full = Path.Combine(root, p.RelPath);
            var parent = Path.GetDirectoryName(full);
            if (!string.IsNullOrEmpty(parent))
                Directory.CreateDirectory(parent);
            File.WriteAllText(full, p.Content);
            if (p.ActionKind == Action.Create)
                created++;
            else
                updated++;
        }

        Console.Out.WriteLine("envdoctor fix\n");
        foreach (var p in plans)
        {
            switch (p.ActionKind)
            {
                case Action.Skip:
                    Console.Out.WriteLine($"  · skipped {p.RelPath} (exists; use --force to overwrite)");
                    break;
                case Action.Create:
                    Console.Out.WriteLine($"  ✓ created {p.RelPath}");
                    break;
                case Action.Update:
                    Console.Out.WriteLine($"  ✓ updated {p.RelPath}");
                    break;
            }
        }
        var errors = findings.Count(f => f.Severity == Severity.Error);
        Console.Out.WriteLine($"\n  {created} created, {updated} updated · {errors} error{Plural(errors)} still present");

        return exitCode;
    }

    private static PlannedFile Plan(string root, string relPath, string content, FixArgs args)
    {
        var exists = File.Exists(Path.Combine(root, relPath));
        var action = !exists ? Action.Create : args.Force ? Action.Update : Action.Skip;
        return new PlannedFile(relPath, action, content);
    }

    private static string ActionLabel(Action action) => action switch
    {
        Action.Create => "will create",
        Action.Update => "will update",
        _ => "exists",
    };

    private static string Plural(int n) => n == 1 ? "" : "s";
}
