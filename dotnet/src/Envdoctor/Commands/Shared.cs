using Envdoctor.Core;
using Envdoctor.Formatters;
using Envdoctor.Models;

namespace Envdoctor.Commands;

public enum OutputFormat
{
    Human,
    Json,
    Sarif,
}

public sealed class OutputArgs
{
    public OutputFormat Format { get; set; } = OutputFormat.Human;
    public string? Output { get; set; }
    public bool Strict { get; set; }

    public OutputArgs Clone() => (OutputArgs)MemberwiseClone();
}

public static class Shared
{
    /// The normalized environment label for a user-supplied diff/sync argument.
    public static string NormalizeEnvLabel(string label) => label.Trim() switch
    {
        "dev" => "development",
        "prod" => "production",
        var other => other,
    };

    /// Report files that could not be parsed, without failing the command.
    public static void ReportParseErrors(ProjectModel model, string root)
    {
        foreach (var pe in model.ParseErrors)
            Console.Error.WriteLine($"⚠ {pe.FilePath}: {pe.Error}");
    }

    /// Output findings in the specified format.
    public static int OutputFindings(string root, OutputArgs args, List<Finding> findings, AuditSummary summary) =>
        OutputFindingsVerbose(root, args, findings, summary, false);

    /// Output findings, with control over whether the human report shows
    /// per-finding `file:line` locations.
    public static int OutputFindingsVerbose(
        string root,
        OutputArgs args,
        List<Finding> findings,
        AuditSummary summary,
        bool verbose)
    {
        // Apply strict mode
        var finalFindings = args.Strict
            ? findings.Select(f =>
            {
                var clone = f.Clone();
                if (clone.Severity == Severity.Warning)
                    clone.Severity = Severity.Error;
                return clone;
            }).ToList()
            : findings;

        string output = args.Format switch
        {
            OutputFormat.Json => JsonFormatter.RenderAuditResultJson(new AuditResult
            {
                Findings = finalFindings,
                Summary = summary,
                ExitCode = ExitCodes.AuditExitCode(new ExitContext { Findings = finalFindings, Strict = args.Strict }),
            }),
            OutputFormat.Sarif => SarifFormatter.RenderSarif(finalFindings, root),
            _ => HumanFormatter.RenderReport(finalFindings, summary, root, verbose),
        };

        if (args.Output is { } path)
            File.WriteAllText(path, output);
        else
            Console.Out.WriteLine(output);

        return ExitCodes.AuditExitCode(new ExitContext { Findings = finalFindings, Strict = args.Strict });
    }
}
