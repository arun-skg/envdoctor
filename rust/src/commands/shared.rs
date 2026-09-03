use crate::models::{AuditResult, AuditSummary, Finding, ProjectModel, Severity};
use crate::formatters::{render_report, render_audit_result_json, render_sarif};
use camino::Utf8PathBuf;
use clap::Args;

/// The normalized environment label for a user-supplied diff/sync argument.
pub fn normalize_env_label(label: &str) -> String {
    match label.trim() {
        "dev" => "development".to_string(),
        "prod" => "production".to_string(),
        other => other.to_string(),
    }
}

/// Report files that could not be parsed, without failing the command.
pub fn report_parse_errors(model: &ProjectModel, _root: &Utf8PathBuf) {
    for pe in &model.parse_errors {
        eprintln!("⚠ {}: {}", pe.file_path, pe.error);
    }
}

#[derive(Args, Debug, Clone, Default)]
pub struct OutputArgs {
    /// Output format
    #[arg(long, value_enum, default_value_t = OutputFormat::Human)]
    pub format: OutputFormat,

    /// Write output to file instead of stdout
    #[arg(long)]
    pub output: Option<Utf8PathBuf>,

    /// Fail on warnings (strict mode)
    #[arg(long)]
    pub strict: bool,
}

#[derive(clap::ValueEnum, Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum OutputFormat {
    #[default]
    Human,
    Json,
    Sarif,
}

impl std::fmt::Display for OutputFormat {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OutputFormat::Human => write!(f, "human"),
            OutputFormat::Json => write!(f, "json"),
            OutputFormat::Sarif => write!(f, "sarif"),
        }
    }
}

/// Output findings in the specified format.
pub fn output_findings(
    root: &Utf8PathBuf,
    args: &OutputArgs,
    findings: &[Finding],
    summary: &AuditSummary,
) -> Result<u8, anyhow::Error> {
    output_findings_verbose(root, args, findings, summary, false)
}

/// Output findings, with control over whether the human report shows
/// per-finding `file:line` locations.
pub fn output_findings_verbose(
    root: &Utf8PathBuf,
    args: &OutputArgs,
    findings: &[Finding],
    summary: &AuditSummary,
    verbose: bool,
) -> Result<u8, anyhow::Error> {
    // Apply strict mode
    let final_findings: Vec<Finding> = if args.strict {
        findings.iter().map(|f| {
            let mut f = f.clone();
            if f.severity == Severity::Warning {
                f.severity = Severity::Error;
            }
            f
        }).collect()
    } else {
        findings.to_vec()
    };

    let output = match args.format {
        OutputFormat::Human => render_report(&final_findings, summary, root, verbose),
        OutputFormat::Json => render_audit_result_json(&AuditResult {
            findings: final_findings.clone(),
            summary: summary.clone(),
            exit_code: crate::core::exit_codes::audit_exit_code(&crate::models::ExitContext {
                findings: final_findings.clone(),
                strict: args.strict,
            }),
        }),
        OutputFormat::Sarif => render_sarif(&final_findings, root),
    };

    if let Some(path) = &args.output {
        std::fs::write(path, output)?;
    } else {
        println!("{}", output);
    }

    let exit_ctx = crate::models::ExitContext {
        findings: final_findings,
        strict: args.strict,
    };
    Ok(crate::core::exit_codes::audit_exit_code(&exit_ctx))
}