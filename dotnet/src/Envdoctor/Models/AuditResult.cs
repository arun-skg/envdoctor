namespace Envdoctor.Models;

/// A single problem found by a detector. `message` is written for humans and
/// must never contain a variable value.
public sealed class Finding
{
    public required string Id { get; set; }
    public required string RuleId { get; set; }
    public Severity Severity { get; set; }
    public required string Variable { get; set; }
    public required string Message { get; set; }
    public List<Origin> Locations { get; set; } = new();

    public static Finding New(
        string ruleId,
        Severity severity,
        string variable,
        string message,
        List<Origin> locations) =>
        new()
        {
            Id = $"{ruleId}.{variable}",
            RuleId = ruleId,
            Severity = severity,
            Variable = variable,
            Message = message,
            Locations = locations,
        };

    public Finding Clone() =>
        new()
        {
            Id = Id,
            RuleId = RuleId,
            Severity = Severity,
            Variable = Variable,
            Message = Message,
            Locations = Locations.Select(o => o.Clone()).ToList(),
        };
}

public enum Severity
{
    Error,
    Warning,
    Info,
}

public static class SeverityExtensions
{
    public static string AsStr(this Severity s) => s switch
    {
        Severity.Error => "error",
        Severity.Warning => "warning",
        Severity.Info => "info",
        _ => "info",
    };
}

public sealed class AuditSummary
{
    public int FilesScanned { get; set; }
    public int VariablesFound { get; set; }
    public int Errors { get; set; }
    public int Warnings { get; set; }
    public int Infos { get; set; }
    public int Total { get; set; }

    public AuditSummary Clone() => (AuditSummary)MemberwiseClone();
}

public sealed class AuditResult
{
    public List<Finding> Findings { get; set; } = new();
    public AuditSummary Summary { get; set; } = new();
    /// 0 = clean, 1 = errors, (2 is reserved for usage/config errors).
    public int ExitCode { get; set; }
}

public sealed class ExitContext
{
    public List<Finding> Findings { get; set; } = new();
    public bool Strict { get; set; }
}
