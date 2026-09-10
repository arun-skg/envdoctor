using Envdoctor.Models;

namespace Envdoctor.Core;

/// Exit codes are part of the public contract — CI pipelines depend on them.
public static class ExitCodes
{
    public const int ExitOk = 0;
    public const int ExitIssues = 1;
    public const int ExitUsage = 2;

    /// Compute the exit code for an audit result given strictness.
    public static int AuditExitCode(ExitContext ctx)
    {
        if (ctx.Findings.Any(f => f.Severity == Severity.Error))
            return ExitIssues;
        if (ctx.Strict && ctx.Findings.Any(f => f.Severity == Severity.Warning))
            return ExitIssues;
        return ExitOk;
    }
}
