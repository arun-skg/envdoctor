use crate::models::{AuditSummary, Finding, Origin};
use camino::Utf8PathBuf;

/// Render a full audit report matching the TypeScript reference `renderReport`
/// (src/utils/logger.ts). Colors are intentionally omitted: the reference uses
/// chalk, which emits no escape codes when stdout is not a TTY, so the plain
/// text produced here is byte-identical to the reference in piped/CI contexts.
pub fn render_report(
    findings: &[Finding],
    summary: &AuditSummary,
    root_dir: &Utf8PathBuf,
    verbose: bool,
) -> String {
    let mut lines: Vec<String> = Vec::new();

    let title = "ENVIRONMENT AUDIT";
    lines.push(title.to_string());
    lines.push("─".repeat(title.chars().count() * 2));
    lines.push(String::new());

    if findings.is_empty() {
        lines.push("  ✓ No issues found".to_string());
        lines.push(String::new());
        lines.push(footer(summary));
        return lines.join("\n");
    }

    for spec in SECTION_SPECS {
        let group: Vec<&Finding> = findings
            .iter()
            .filter(|f| spec.rule_ids.contains(&f.rule_id.as_str()))
            .collect();
        if group.is_empty() {
            continue;
        }
        lines.push(spec.heading.to_string());
        lines.push(String::new());
        for f in group {
            for line in (spec.line)(f, root_dir, verbose) {
                lines.push(line);
            }
        }
        lines.push(String::new());
    }

    lines.push(footer(summary));
    lines.join("\n")
}

struct SectionSpec {
    heading: &'static str,
    rule_ids: &'static [&'static str],
    line: fn(&Finding, &Utf8PathBuf, bool) -> Vec<String>,
}

const SECTION_SPECS: &[SectionSpec] = &[
    SectionSpec {
        heading: "Missing",
        rule_ids: &["missing", "undefined-in-source"],
        line: |f, root, verbose| {
            let where_ = if f.locations.is_empty() {
                "referenced but never defined".to_string()
            } else {
                format!("referenced in {}", join_locations(&f.locations, root))
            };
            let mut lines = vec![format!("  {}  {}", f.variable, where_)];
            lines.extend(location_lines(f, root, verbose));
            lines
        },
    },
    SectionSpec {
        heading: "Defined but unused",
        rule_ids: &["unused"],
        line: |f, root, _| {
            let where_ = if f.locations.is_empty() {
                String::new()
            } else {
                format!("defined in {}", join_locations(&f.locations, root))
            };
            vec![format!("  {}  {}", f.variable, where_)]
        },
    },
    SectionSpec {
        heading: "Duplicates",
        rule_ids: &["duplicates"],
        line: |f, _, _| vec![format!("  {}  {}", f.variable, f.message)],
    },
    SectionSpec {
        heading: "Type mismatch",
        rule_ids: &["type-mismatch"],
        line: |f, _, _| {
            let mut lines = vec![format!("  {}", f.variable)];
            if let Some(expected) = capture_after(&f.message, "expected:") {
                lines.push(format!("    expected: {expected}"));
            }
            if let Some(found) = capture_after(&f.message, "found:") {
                lines.push(format!("    found: {found}"));
            }
            lines
        },
    },
    SectionSpec {
        heading: "Environment differences",
        rule_ids: &["environment-diff"],
        line: |f, _, _| vec![format!("  {}", f.message)],
    },
    SectionSpec {
        heading: "Public secret leak",
        rule_ids: &["public-prefix"],
        line: |f, root, verbose| {
            let mut lines = vec![format!("  {}", f.variable)];
            lines.extend(location_lines(f, root, verbose));
            lines
        },
    },
    SectionSpec {
        heading: "Weak secrets",
        rule_ids: &["weak-secret"],
        line: |f, _, _| vec![format!("  {}  {}", f.variable, f.message)],
    },
    SectionSpec {
        heading: "Possible typos",
        rule_ids: &["typo"],
        line: |f, root, verbose| {
            let mut lines = vec![format!("  {}  {}", f.variable, f.message)];
            lines.extend(location_lines(f, root, verbose));
            lines
        },
    },
    SectionSpec {
        heading: "Schema validation",
        rule_ids: &["schema-validation"],
        line: |f, root, verbose| {
            let mut lines = vec![format!("  {}  {}", f.variable, f.message)];
            lines.extend(location_lines(f, root, verbose));
            lines
        },
    },
];

/// Verbose-only location lines: `  · path:line`, capped at the first 3.
fn location_lines(f: &Finding, root: &Utf8PathBuf, verbose: bool) -> Vec<String> {
    if !verbose || f.locations.is_empty() {
        return Vec::new();
    }
    f.locations
        .iter()
        .take(3)
        .map(|o| format!("  · {}", render_location(root, o)))
        .collect()
}

fn join_locations(locations: &[Origin], root: &Utf8PathBuf) -> String {
    locations
        .iter()
        .map(|o| render_location(root, o))
        .collect::<Vec<_>>()
        .join(", ")
}

/// Render a single location as `relative/path:line`, matching the reference
/// `renderLocation` + `displayPath` (absolute fallback when not under root).
fn render_location(root: &Utf8PathBuf, origin: &Origin) -> String {
    let path = display_path(root, &origin.file_path);
    match origin.line {
        Some(line) => format!("{path}:{line}"),
        None => path,
    }
}

fn display_path(root: &Utf8PathBuf, file_path: &Utf8PathBuf) -> String {
    match file_path.strip_prefix(root) {
        Ok(rel) if !rel.as_str().is_empty() => rel.as_str().to_string(),
        _ => file_path.as_str().to_string(),
    }
}

fn footer(summary: &AuditSummary) -> String {
    let errors = if summary.errors > 0 {
        format!("{} error{}", summary.errors, plural(summary.errors))
    } else {
        "0 errors".to_string()
    };
    let warnings = if summary.warnings > 0 {
        format!("{} warning{}", summary.warnings, plural(summary.warnings))
    } else {
        "0 warnings".to_string()
    };
    format!(
        "Summary: {} files scanned · {} variables · {} · {}",
        summary.files_scanned, summary.variables_found, errors, warnings
    )
}

fn plural(n: usize) -> &'static str {
    if n == 1 {
        ""
    } else {
        "s"
    }
}

/// Extract the token after a label like `expected:` / `found:` (letters only,
/// case-insensitive), mirroring the reference regex `/label\s*([a-z]+)/i`.
fn capture_after(message: &str, label: &str) -> Option<String> {
    let lower = message.to_lowercase();
    let idx = lower.find(&label.to_lowercase())?;
    let rest = &message[idx + label.len()..];
    let rest = rest.trim_start();
    let word: String = rest.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    if word.is_empty() {
        None
    } else {
        Some(word)
    }
}

/// A compact one-line summary for CI logs.
pub fn render_summary_line(summary: &AuditSummary) -> String {
    format!(
        "{} errors, {} warnings, {} info",
        summary.errors, summary.warnings, summary.infos
    )
}
