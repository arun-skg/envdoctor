using Envdoctor.Core;
using Envdoctor.Models;
using Envdoctor.Runtime;
using Envdoctor.Utils;

namespace Envdoctor.Commands;

public sealed class SnapshotDiffArgs
{
    public string? Root { get; set; }
    public string A { get; set; } = "";
    public string B { get; set; } = "";
    public bool Json { get; set; }
}

public static class SnapshotDiffCommand
{
    /// Resolve a positional arg that may be a token string or a file path.
    private static RuntimeSnapshot LoadSnapshot(string root, string arg)
    {
        if (arg.Trim().StartsWith("envd1:", StringComparison.Ordinal))
            return Token.DecodeToken(arg);
        var file = Path.Combine(root, arg);
        if (!File.Exists(file))
            throw new SnapshotTokenException($"Not a snapshot token, and file not found: {arg}");
        return Token.ParseSnapshotJson(File.ReadAllText(file));
    }

    /// `envdoctor snapshot-diff <a> <b>` — compare two runtime snapshots.
    public static int Run(SnapshotDiffArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        RuntimeSnapshot a;
        RuntimeSnapshot b;
        try
        {
            a = LoadSnapshot(root, args.A);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"error {e.Message}");
            return ExitCodes.ExitUsage;
        }
        try
        {
            b = LoadSnapshot(root, args.B);
        }
        catch (Exception e)
        {
            Console.Error.WriteLine($"error {e.Message}");
            return ExitCodes.ExitUsage;
        }

        var diff = Compare.CompareSnapshots(a, b);
        var exitCode = diff.Equivalent ? ExitCodes.ExitOk : ExitCodes.ExitIssues;

        if (args.Json)
        {
            Console.Out.WriteLine(DiffToJson(diff, exitCode));
            return exitCode;
        }

        RenderHuman(diff);
        return exitCode;
    }

    private static string DiffToJson(RuntimeDiff diff, int exitCode)
    {
        var globals = diff.Globals.Select(g =>
        {
            var obj = new JsonObject
            {
                { "ecosystem", g.Ecosystem },
                { "name", g.Name },
                { "status", g.Status.AsStr() },
            };
            if (g.A is not null)
                obj.Add("a", g.A);
            if (g.B is not null)
                obj.Add("b", g.B);
            return (object)obj;
        }).ToList();

        var tools = diff.Tools.Select(t =>
        {
            var obj = new JsonObject
            {
                { "name", t.Name },
                { "status", t.Status.AsStr() },
            };
            if (t.A is not null)
                obj.Add("a", t.A);
            if (t.B is not null)
                obj.Add("b", t.B);
            return (object)obj;
        }).ToList();

        // exitCode first, matching the reference CLI's key order.
        return Json.Pretty(new JsonObject
        {
            { "exitCode", exitCode },
            {
                "os", new JsonObject
                {
                    { "status", diff.Os.Status.AsStr() },
                    { "a", diff.Os.A },
                    { "b", diff.Os.B },
                }
            },
            { "tools", tools },
            { "pathReordered", diff.PathReordered },
            { "pathOnlyA", diff.PathOnlyA.Cast<object?>().ToList() },
            { "pathOnlyB", diff.PathOnlyB.Cast<object?>().ToList() },
            { "globals", globals },
            { "envFlagOnlyA", diff.EnvFlagOnlyA.Cast<object?>().ToList() },
            { "envFlagOnlyB", diff.EnvFlagOnlyB.Cast<object?>().ToList() },
            { "equivalent", diff.Equivalent },
        });
    }

    private static void RenderHuman(RuntimeDiff diff)
    {
        const string title = "RUNTIME DIFF";
        Console.Out.WriteLine(title);
        Console.Out.WriteLine(new string('─', title.Length * 2) + "\n");
        Console.Out.WriteLine("  A → B\n");

        if (diff.Os.Status == RuntimeStatus.Same)
            Console.Out.WriteLine($"  ✓ OS  {diff.Os.A}\n");
        else
            Console.Out.WriteLine($"  ⚠ OS  {diff.Os.A} → {diff.Os.B}\n");

        Console.Out.WriteLine("  Tools");
        foreach (var t in diff.Tools)
        {
            var a = t.A ?? "";
            var b = t.B ?? "";
            switch (t.Status)
            {
                case RuntimeStatus.Same:
                    Console.Out.WriteLine($"  ✓ {t.Name,-8} {a}");
                    break;
                case RuntimeStatus.Different:
                    Console.Out.WriteLine($"  ⚠ {t.Name,-8} {a} → {b}");
                    break;
                case RuntimeStatus.OnlyA:
                    Console.Out.WriteLine($"  ❌ {t.Name,-8} missing in B (A: {a})");
                    break;
                case RuntimeStatus.OnlyB:
                    Console.Out.WriteLine($"  ❌ {t.Name,-8} missing in A (B: {b})");
                    break;
            }
        }

        if (diff.PathReordered || diff.PathOnlyA.Count > 0 || diff.PathOnlyB.Count > 0)
        {
            Console.Out.WriteLine("\n  PATH");
            if (diff.PathReordered)
                Console.Out.WriteLine("  ⚠ same entries, different order");
            foreach (var p in diff.PathOnlyA)
                Console.Out.WriteLine($"  ❌ only in A: {p}");
            foreach (var p in diff.PathOnlyB)
                Console.Out.WriteLine($"  ❌ only in B: {p}");
        }

        if (diff.Globals.Count > 0)
        {
            Console.Out.WriteLine("\n  Globals");
            foreach (var g in diff.Globals)
            {
                var label = $"{g.Ecosystem}:{g.Name}";
                switch (g.Status)
                {
                    case RuntimeStatus.Different:
                        Console.Out.WriteLine($"  ⚠ {label}  {g.A ?? ""} → {g.B ?? ""}");
                        break;
                    case RuntimeStatus.OnlyA:
                        Console.Out.WriteLine($"  ❌ {label}  missing in B");
                        break;
                    case RuntimeStatus.OnlyB:
                        Console.Out.WriteLine($"  ❌ {label}  missing in A");
                        break;
                    case RuntimeStatus.Same:
                        break;
                }
            }
        }

        Console.Out.WriteLine(diff.Equivalent
            ? "\n  ✓ runtimes are equivalent"
            : "\n  ✗ runtime drift detected");
    }
}
