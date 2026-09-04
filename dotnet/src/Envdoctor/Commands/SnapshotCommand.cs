using Envdoctor.Core;
using Envdoctor.Runtime;
using Envdoctor.Utils;

namespace Envdoctor.Commands;

public sealed class SnapshotArgs
{
    public string? Root { get; set; }
    public string? Output { get; set; }
    public bool Token { get; set; }
    public bool Json { get; set; }
    public bool Globals { get; set; }
}

public static class SnapshotCommand
{
    /// `envdoctor snapshot` — capture this machine's live runtime.
    public static int Run(SnapshotArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        var snapshot = Capture.CaptureSnapshot(args.Globals);

        if (args.Output is { } output)
        {
            var dest = Path.Combine(root, output);
            File.WriteAllText(dest, SnapshotJsonPretty(snapshot) + "\n");
            Console.Error.WriteLine($"✓ Snapshot written to {output}");
        }

        if (args.Json)
        {
            Console.Out.WriteLine(SnapshotJsonPretty(snapshot));
            return ExitCodes.ExitOk;
        }

        if (args.Token)
        {
            Console.Out.WriteLine(Runtime.Token.EncodeToken(snapshot));
            return ExitCodes.ExitOk;
        }

        // Human summary.
        const string title = "RUNTIME SNAPSHOT";
        Console.Out.WriteLine(title);
        Console.Out.WriteLine(new string('─', title.Length * 2) + "\n");
        Console.Out.WriteLine($"  OS  {snapshot.Os.Platform}/{snapshot.Os.Arch} {snapshot.Os.Release}\n");

        Console.Out.WriteLine("  Tools");
        if (snapshot.Tools.Count == 0)
        {
            Console.Out.WriteLine("  none detected");
        }
        else
        {
            foreach (var t in snapshot.Tools)
                Console.Out.WriteLine($"  ✓ {t.Tool,-8} {t.Version}  {t.ResolvedFrom}");
        }

        Console.Out.WriteLine($"\n  PATH ({snapshot.Path.Count} entries)");
        var index = 0;
        foreach (var p in snapshot.Path.Take(12))
        {
            index++;
            Console.Out.WriteLine($"  {index,2}  {p}");
        }
        if (snapshot.Path.Count > 12)
            Console.Out.WriteLine($"  … {snapshot.Path.Count - 12} more");

        var ecosystems = snapshot.Globals.Keys.ToList();
        if (ecosystems.Count > 0)
        {
            Console.Out.WriteLine("\n  Globals");
            foreach (var eco in ecosystems)
                Console.Out.WriteLine($"  {eco}: {snapshot.Globals[eco].Count} packages");
        }
        else if (!args.Globals)
        {
            Console.Out.WriteLine("\n  Globals omitted — pass --globals to include the package inventory.");
        }

        Console.Out.WriteLine("\n  Share with:  envdoctor snapshot --token   ·   compare with:  envdoctor snapshot-diff <a> <b>");

        return ExitCodes.ExitOk;
    }

    private static string SnapshotJsonPretty(Models.RuntimeSnapshot snapshot)
    {
        // Pretty-print the same shape the token codec emits compactly.
        var compact = Runtime.Token.SnapshotToJson(snapshot);
        using var doc = System.Text.Json.JsonDocument.Parse(compact);
        return Json.Pretty(ToPlain(doc.RootElement));
    }

    private static object? ToPlain(System.Text.Json.JsonElement el) => el.ValueKind switch
    {
        System.Text.Json.JsonValueKind.Object => el.EnumerateObject()
            .Aggregate(new JsonObject(), (obj, p) =>
            {
                obj.Add(p.Name, ToPlain(p.Value));
                return obj;
            }),
        System.Text.Json.JsonValueKind.Array => el.EnumerateArray().Select(ToPlain).ToList(),
        System.Text.Json.JsonValueKind.String => el.GetString(),
        System.Text.Json.JsonValueKind.Number => el.TryGetInt64(out var l) ? l : el.GetDouble(),
        System.Text.Json.JsonValueKind.True => true,
        System.Text.Json.JsonValueKind.False => false,
        _ => null,
    };
}
