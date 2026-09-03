use crate::models::{ExitContext, Severity};

/// Exit codes are part of the public contract — CI pipelines depend on them.
///
/// - 0: audit ran and found nothing that fails
/// - 1: audit found error-severity findings (or warnings under --strict)
/// - 2: usage/config error (bad arguments, unreadable config)
pub const EXIT_OK: u8 = 0;
pub const EXIT_ISSUES: u8 = 1;
pub const EXIT_USAGE: u8 = 2;

/// Compute the exit code for an audit result given strictness.
pub fn audit_exit_code(ctx: &ExitContext) -> u8 {
    let has_errors = ctx.findings.iter().any(|f| f.severity == Severity::Error);
    if has_errors {
        return EXIT_ISSUES;
    }
    if ctx.strict && ctx.findings.iter().any(|f| f.severity == Severity::Warning) {
        return EXIT_ISSUES;
    }
    EXIT_OK
}