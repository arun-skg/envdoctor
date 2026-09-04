using Envdoctor.Core;
using Envdoctor.Detectors;
using Envdoctor.Formatters;
using Envdoctor.Models;
using Envdoctor.Utils;

namespace Envdoctor.Commands;

public sealed class ScanArgs
{
    public OutputArgs Output { get; set; } = new();
    public string? Root { get; set; }
    public bool Verbose { get; set; }
    public List<string> Only { get; set; } = new();
    public string? Baseline { get; set; }
    public string? WriteBaseline { get; set; }
    public bool Staged { get; set; }
    public string? Since { get; set; }
    public bool Json { get; set; }
}

public static class ScanCommand
{
    public static int Run(ScanArgs args)
    {
        var root = Path.GetFullPath(args.Root ?? ".");

        // Warn about unknown detector ids passed via --only.
        var known = Audit.AllDetectors().Select(d => d.Id).ToHashSet();
        foreach (var rule in args.Only)
        {
            if (!known.Contains(rule))
            {
                var ids = known.ToList();
                ids.Sort(StringComparer.Ordinal);
                Console.Error.WriteLine($"warning Unknown detector \"{rule}\" (known: {string.Join(", ", ids)})");
            }
        }

        // Determine a git-changed file filter for --staged / --since.
        HashSet<string>? changed = args.Staged
            ? Discover.StagedFiles(root).ToHashSet()
            : args.Since is { } since
                ? Discover.ChangedFilesSince(root, since).ToHashSet()
                : null;
        var filterActive = changed is not null;

        var (model, config) = Pipeline.LoadProjectFiltered(root, changed);

        if (filterActive && model.AllFiles.Count == 0)
        {
            Console.Out.WriteLine("✓ No changed env-related files to scan");
            return 0;
        }

        var index = IndexedModel.BuildIndex(model);
        var findings = Audit.RunAudit(model, config, index);

        Shared.ReportParseErrors(model, root);

        // --only: restrict to the requested detector ids.
        if (args.Only.Count > 0)
        {
            var only = args.Only.ToHashSet();
            findings = findings.Where(f => only.Contains(f.RuleId)).ToList();
        }

        // --baseline: suppress previously-recorded findings.
        if (args.Baseline is { } baselinePath)
            findings = ApplyBaseline(findings, root, baselinePath);

        // --write-baseline: persist the current findings as a baseline.
        if (args.WriteBaseline is { } writePath)
            WriteBaselineFile(findings, root, writePath);

        var summary = Pipeline.Summarize(model, findings);

        // --json is an alias for --format json.
        var output = args.Output.Clone();
        if (args.Json)
            output.Format = OutputFormat.Json;

        // JSON output uses a stable, camelCase projection matching the
        // reference CLI (rather than the internal snake_case model shape).
        if (output.Format == OutputFormat.Json)
        {
            // Under --strict, warnings are promoted to errors for the exit code.
            var finalFindings = output.Strict
                ? findings.Select(f =>
                {
                    var clone = f.Clone();
                    if (clone.Severity == Severity.Warning)
                        clone.Severity = Severity.Error;
                    return clone;
                }).ToList()
                : findings;
            var exit = ExitCodes.AuditExitCode(new ExitContext { Findings = finalFindings, Strict = output.Strict });
            var json = RenderScanJson(root, finalFindings, summary, exit);
            if (output.Output is { } path)
                File.WriteAllText(path, json + "\n");
            else
                Console.Out.WriteLine(json);
            return exit;
        }

        return Shared.OutputFindingsVerbose(root, output, findings, summary, args.Verbose);
    }

    /// Render the scan result as the reference CLI's JSON shape.
    private static string RenderScanJson(string root, List<Finding> findings, AuditSummary summary, int exitCode)
    {
        var findingsJson = findings.Select(f =>
        {
            var locations = f.Locations.Select(o =>
            {
                var loc = new JsonObject { { "file", HumanFormatter.DisplayPath(root, o.FilePath) } };
                if (o.Line is { } line)
                    loc.Add("line", line);
                loc.Add("kind", o.Kind.AsStr());
                return (object)loc;
            }).ToList();
            return (object)new JsonObject
            {
                { "id", f.Id },
                { "ruleId", f.RuleId },
                { "severity", f.Severity.AsStr() },
                { "variable", f.Variable },
                { "message", f.Message },
                { "locations", locations },
            };
        }).ToList();

        return Json.Pretty(new JsonObject
        {
            { "exitCode", exitCode },
            {
                "summary", new JsonObject
                {
                    { "filesScanned", summary.FilesScanned },
                    { "variablesFound", summary.VariablesFound },
                    { "errors", summary.Errors },
                    { "warnings", summary.Warnings },
                    { "infos", summary.Infos },
                    { "total", summary.Total },
                }
            },
            { "findings", findingsJson },
        });
    }

    private sealed record BaselineEntry(string RuleId, string Variable, List<string> Files);

    private sealed class BaselineFile
    {
        public int Version { get; set; }
        public List<BaselineEntry> Findings { get; set; } = new();
    }

    private static BaselineEntry Fingerprint(string root, Finding finding)
    {
        var files = finding.Locations
            .Select(o => HumanFormatter.DisplayPath(root, o.FilePath))
            .Distinct()
            .ToList();
        files.Sort(StringComparer.Ordinal);
        return new BaselineEntry(finding.RuleId, finding.Variable, files);
    }

    private static bool EntryMatches(BaselineEntry a, BaselineEntry b) =>
        a.RuleId == b.RuleId && a.Variable == b.Variable && a.Files.SequenceEqual(b.Files);

    private static List<Finding> ApplyBaseline(List<Finding> findings, string root, string baselinePath)
    {
        var full = Path.Combine(root, baselinePath);
        BaselineFile? baseline = null;
        try
        {
            var raw = File.ReadAllText(full);
            using var doc = System.Text.Json.JsonDocument.Parse(raw);
            var rootEl = doc.RootElement;
            baseline = new BaselineFile
            {
                Version = rootEl.TryGetProperty("version", out var v) ? v.GetInt32() : 0,
                Findings = rootEl.TryGetProperty("findings", out var f) && f.ValueKind == System.Text.Json.JsonValueKind.Array
                    ? f.EnumerateArray().Select(e => new BaselineEntry(
                        e.GetProperty("rule_id").GetString() ?? "",
                        e.GetProperty("variable").GetString() ?? "",
                        e.GetProperty("files").EnumerateArray().Select(x => x.GetString() ?? "").ToList()))
                        .ToList()
                    : new List<BaselineEntry>(),
            };
        }
        catch
        {
            baseline = null;
        }

        if (baseline is null)
        {
            Console.Error.WriteLine($"warning Could not read baseline {baselinePath}");
            return findings;
        }

        var before = findings.Count;
        var kept = findings
            .Where(f => !baseline.Findings.Any(b => EntryMatches(b, Fingerprint(root, f))))
            .ToList();
        var suppressed = before - kept.Count;
        if (suppressed > 0)
        {
            Console.Error.WriteLine(
                $"info {suppressed} finding{(suppressed == 1 ? "" : "s")} suppressed by baseline");
        }
        return kept;
    }

    private static void WriteBaselineFile(List<Finding> findings, string root, string baselinePath)
    {
        var full = Path.Combine(root, baselinePath);
        var baseline = new JsonObject
        {
            { "version", 1 },
            {
                "findings", findings
                    .Select(f =>
                    {
                        var fp = Fingerprint(root, f);
                        return (object)new JsonObject
                        {
                            { "rule_id", fp.RuleId },
                            { "variable", fp.Variable },
                            { "files", fp.Files.Cast<object?>().ToList() },
                        };
                    })
                    .ToList()
            },
        };
        var parent = Path.GetDirectoryName(full);
        if (!string.IsNullOrEmpty(parent))
            Directory.CreateDirectory(parent);
        File.WriteAllText(full, Json.Pretty(baseline) + "\n");
        Console.Error.WriteLine($"info Wrote baseline to {baselinePath}");
    }
}
