using System.Text;
using System.Text.RegularExpressions;
using Envdoctor.Models;

namespace Envdoctor.Formatters;

/// Render a full audit report matching the TypeScript reference `renderReport`
/// (src/utils/logger.ts). Colors are intentionally omitted: the reference uses
/// chalk, which emits no escape codes when stdout is not a TTY, so the plain
/// text produced here is byte-identical to the reference in piped/CI contexts.
public static class HumanFormatter
{
    private delegate List<string> LineRenderer(Finding f, string root, bool verbose);

    private sealed record SectionSpec(string Heading, string[] RuleIds, LineRenderer Line);

    private static readonly SectionSpec[] SectionSpecs =
    {
        new("Missing", new[] { "missing", "undefined-in-source" }, (f, root, verbose) =>
        {
            var where = f.Locations.Count == 0
                ? "referenced but never defined"
                : $"referenced in {JoinLocations(f.Locations, root)}";
            var lines = new List<string> { $"  {f.Variable}  {where}" };
            lines.AddRange(LocationLines(f, root, verbose));
            return lines;
        }),
        new("Defined but unused", new[] { "unused" }, (f, root, _) =>
        {
            var where = f.Locations.Count == 0
                ? ""
                : $"defined in {JoinLocations(f.Locations, root)}";
            return new List<string> { $"  {f.Variable}  {where}" };
        }),
        new("Duplicates", new[] { "duplicates" }, (f, _, _) =>
            new List<string> { $"  {f.Variable}  {f.Message}" }),
        new("Type mismatch", new[] { "type-mismatch" }, (f, _, _) =>
        {
            var lines = new List<string> { $"  {f.Variable}" };
            if (CaptureAfter(f.Message, "expected:") is { } expected)
                lines.Add($"    expected: {expected}");
            if (CaptureAfter(f.Message, "found:") is { } found)
                lines.Add($"    found: {found}");
            return lines;
        }),
        new("Environment differences", new[] { "environment-diff" }, (f, _, _) =>
            new List<string> { $"  {f.Message}" }),
        new("Public secret leak", new[] { "public-prefix" }, (f, root, verbose) =>
        {
            var lines = new List<string> { $"  {f.Variable}" };
            lines.AddRange(LocationLines(f, root, verbose));
            return lines;
        }),
        new("Weak secrets", new[] { "weak-secret" }, (f, _, _) =>
            new List<string> { $"  {f.Variable}  {f.Message}" }),
        new("Possible typos", new[] { "typo" }, (f, root, verbose) =>
        {
            var lines = new List<string> { $"  {f.Variable}  {f.Message}" };
            lines.AddRange(LocationLines(f, root, verbose));
            return lines;
        }),
        new("Schema validation", new[] { "schema-validation" }, (f, root, verbose) =>
        {
            var lines = new List<string> { $"  {f.Variable}  {f.Message}" };
            lines.AddRange(LocationLines(f, root, verbose));
            return lines;
        }),
    };

    public static string RenderReport(IReadOnlyList<Finding> findings, AuditSummary summary, string rootDir, bool verbose)
    {
        var lines = new List<string>();

        const string title = "ENVIRONMENT AUDIT";
        lines.Add(title);
        lines.Add(new string('─', title.Length * 2));
        lines.Add("");

        if (findings.Count == 0)
        {
            lines.Add("  ✓ No issues found");
            lines.Add("");
            lines.Add(Footer(summary));
            return string.Join("\n", lines);
        }

        foreach (var spec in SectionSpecs)
        {
            var group = findings.Where(f => spec.RuleIds.Contains(f.RuleId)).ToList();
            if (group.Count == 0)
                continue;
            lines.Add(spec.Heading);
            lines.Add("");
            foreach (var f in group)
                lines.AddRange(spec.Line(f, rootDir, verbose));
            lines.Add("");
        }

        lines.Add(Footer(summary));
        return string.Join("\n", lines);
    }

    /// Verbose-only location lines: `  · path:line`, capped at the first 3.
    private static List<string> LocationLines(Finding f, string root, bool verbose)
    {
        if (!verbose || f.Locations.Count == 0)
            return new List<string>();
        return f.Locations.Take(3).Select(o => $"  · {RenderLocation(root, o)}").ToList();
    }

    private static string JoinLocations(IReadOnlyList<Origin> locations, string root) =>
        string.Join(", ", locations.Select(o => RenderLocation(root, o)));

    /// Render a single location as `relative/path:line`.
    public static string RenderLocation(string root, Origin origin)
    {
        var path = DisplayPath(root, origin.FilePath);
        return origin.Line is { } line ? $"{path}:{line}" : path;
    }

    public static string DisplayPath(string root, string filePath)
    {
        var rel = Core.Discover.RelativeTo(root, filePath);
        return !string.IsNullOrEmpty(rel) ? rel : filePath;
    }

    private static string Footer(AuditSummary summary)
    {
        var errors = summary.Errors > 0 ? $"{summary.Errors} error{Plural(summary.Errors)}" : "0 errors";
        var warnings = summary.Warnings > 0 ? $"{summary.Warnings} warning{Plural(summary.Warnings)}" : "0 warnings";
        return $"Summary: {summary.FilesScanned} files scanned · {summary.VariablesFound} variables · {errors} · {warnings}";
    }

    private static string Plural(int n) => n == 1 ? "" : "s";

    /// Extract the token after a label like `expected:` / `found:` (letters
    /// only, case-insensitive), mirroring the reference regex `/label\s*([a-z]+)/i`.
    private static string? CaptureAfter(string message, string label)
    {
        var idx = message.IndexOf(label, StringComparison.OrdinalIgnoreCase);
        if (idx < 0)
            return null;
        var rest = message[(idx + label.Length)..].TrimStart();
        var sb = new StringBuilder();
        foreach (var c in rest)
        {
            if (!char.IsAsciiLetter(c))
                break;
            sb.Append(c);
        }
        return sb.Length == 0 ? null : sb.ToString();
    }
}
