use crate::models::{AuditSummary, Finding, Severity};
use colored::Colorize;

/// Render a human-readable audit report.
pub fn render_report(
    findings: &[Finding],
    summary: &AuditSummary,
    root_dir: &camino::Utf8PathBuf,
    verbose: bool,
) -> String {
    let mut out = String::new();

    if findings.is_empty() {
        out.push_str(&format!("{} No issues found.\n", "✓".green().bold()));
        return out;
    }

    // Group by severity for nicer display
    out.push_str(&format!("\n{}\n", "Audit Report".bold().underline()));
    out.push_str(&format!("Scanned {} files, found {} variables.\n\n",
        summary.files_scanned, summary.variables_found));

    // Sort findings: errors first, then warnings, then info, then by variable
    let mut sorted = findings.to_vec();
    sorted.sort_by(|a, b| {
        severity_order(a.severity).cmp(&severity_order(b.severity))
            .then(a.variable.cmp(&b.variable))
    });

    fn severity_order(s: Severity) -> u8 {
        match s {
            Severity::Error => 0,
            Severity::Warning => 1,
            Severity::Info => 2,
        }
    }

    for f in &sorted {
        out.push_str(&render_finding(f, root_dir, verbose));
        out.push('\n');
    }

    // Summary footer
    out.push('\n');
    if summary.errors > 0 {
        out.push_str(&format!("{} {}\n", "✗".red().bold(), format!("{} error(s)", summary.errors).red()));
    }
    if summary.warnings > 0 {
        out.push_str(&format!("{} {}\n", "!".yellow().bold(), format!("{} warning(s)", summary.warnings).yellow()));
    }
    if summary.infos > 0 {
        out.push_str(&format!("{} {}\n", "i".blue().bold(), format!("{} info(s)", summary.infos).blue()));
    }

    out
}

fn render_finding(f: &Finding, root_dir: &camino::Utf8PathBuf, verbose: bool) -> String {
    let (label, _color) = match f.severity {
        Severity::Error => ("ERROR".red().bold(), "red"),
        Severity::Warning => ("WARN".yellow().bold(), "yellow"),
        Severity::Info => ("INFO".blue().bold(), "blue"),
    };

    let mut s = String::new();
    s.push_str(&format!("{} [{}] {}\n", label, f.rule_id.cyan(), f.variable.bold()));
    s.push_str(&format!("      {}\n", f.message));

    // Locations (only in verbose mode, matching the reference CLI).
    if verbose && !f.locations.is_empty() {
        let locations: Vec<String> = f.locations.iter().take(3).map(|o| {
            let rel = o.file_path.strip_prefix(root_dir)
                .ok()
                .map(|p: &camino::Utf8Path| p.as_str())
                .unwrap_or(o.file_path.as_str());
            match o.line {
                Some(l) => format!("{}:{}", rel, l),
                None => rel.to_string(),
            }
        }).collect();
        s.push_str(&format!("      at {}\n", locations.join(", ")));
    }

    s
}

/// A compact one-line summary for CI logs.
pub fn render_summary_line(summary: &AuditSummary) -> String {
    format!(
        "{} errors, {} warnings, {} info",
        summary.errors, summary.warnings, summary.infos
    )
}

/// Format a severity as a colored string.
#[allow(dead_code)]
pub fn severity_label(sev: &Severity) -> colored::ColoredString {
    match sev {
        Severity::Error => "ERROR".red().bold(),
        Severity::Warning => "WARN".yellow().bold(),
        Severity::Info => "INFO".blue().bold(),
    }
}
