import '../models/finding.dart';

/// Exit codes are part of the public contract — CI pipelines depend on them.
class ExitCodes {
  static const int exitOk = 0;
  static const int exitIssues = 1;
  static const int exitUsage = 2;

  /// Compute the exit code for an audit result given strictness.
  static int auditExitCode(ExitContext ctx) {
    if (ctx.findings.any((f) => f.severity == Severity.error)) return exitIssues;
    if (ctx.strict && ctx.findings.any((f) => f.severity == Severity.warning)) {
      return exitIssues;
    }
    return exitOk;
  }
}
