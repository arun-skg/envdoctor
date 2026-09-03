use crate::commands::shared::{report_parse_errors, OutputArgs, OutputFormat};
use crate::core::audit::{all_detectors, run_audit};
use crate::core::discover::{changed_files_since, staged_files};
use crate::core::pipeline::{load_project_filtered, summarize};
use crate::detectors::index::build_index;
use crate::models::Finding;
use camino::Utf8PathBuf;
use clap::Args;
use std::collections::HashSet;

#[derive(Args, Debug, Default)]
pub struct ScanArgs {
    #[command(flatten)]
    pub output: OutputArgs,

    /// Project root (default: current directory)
    #[arg(long, short = 'C')]
    pub root: Option<Utf8PathBuf>,

    /// Show file:line locations in the report
    #[arg(long, short = 'v')]
    pub verbose: bool,

    /// Restrict the audit to these detector ids (comma-separated)
    #[arg(long, value_delimiter = ',')]
    pub only: Vec<String>,

    /// Suppress findings listed in a baseline file
    #[arg(long)]
    pub baseline: Option<Utf8PathBuf>,

    /// Write the current findings to a baseline file
    #[arg(long)]
    pub write_baseline: Option<Utf8PathBuf>,

    /// Only scan files with staged git changes
    #[arg(long)]
    pub staged: bool,

    /// Only scan files changed since a git ref
    #[arg(long)]
    pub since: Option<String>,

    /// Alias for --format json
    #[arg(long)]
    pub json: bool,
}

pub async fn scan(args: ScanArgs) -> Result<u8, anyhow::Error> {
    let root = args.root.clone().unwrap_or_else(|| Utf8PathBuf::from("."));
    let root: Utf8PathBuf = std::fs::canonicalize(&root)?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid root path"))?;

    // Warn about unknown detector ids passed via --only.
    let known: HashSet<String> = all_detectors().iter().map(|d| d.id().to_string()).collect();
    for rule in &args.only {
        if !known.contains(rule) {
            let mut ids: Vec<&String> = known.iter().collect();
            ids.sort();
            eprintln!(
                "warning Unknown detector \"{}\" (known: {})",
                rule,
                ids.iter().map(|s| s.as_str()).collect::<Vec<_>>().join(", ")
            );
        }
    }

    // Determine a git-changed file filter for --staged / --since.
    let changed: Option<HashSet<Utf8PathBuf>> = if args.staged {
        Some(staged_files(&root).into_iter().collect())
    } else if let Some(since) = &args.since {
        Some(changed_files_since(&root, since).into_iter().collect())
    } else {
        None
    };
    let filter_active = changed.is_some();

    let (model, config) = load_project_filtered(&root, changed.as_ref()).await;

    if filter_active && model.all_files.is_empty() {
        println!("✓ No changed env-related files to scan");
        return Ok(0);
    }

    let index = build_index(&model);
    let mut findings = run_audit(&model, &config, &index);

    report_parse_errors(&model, &root);

    // --only: restrict to the requested detector ids.
    if !args.only.is_empty() {
        let only: HashSet<&str> = args.only.iter().map(|s| s.as_str()).collect();
        findings.retain(|f| only.contains(f.rule_id.as_str()));
    }

    // --baseline: suppress previously-recorded findings.
    if let Some(baseline_path) = &args.baseline {
        findings = apply_baseline(findings, &root, baseline_path);
    }

    // --write-baseline: persist the current findings as a baseline.
    if let Some(path) = &args.write_baseline {
        write_baseline(&findings, &root, path)?;
    }

    let summary = summarize(&model, &findings);

    // --json is an alias for --format json.
    let mut output = args.output.clone();
    if args.json {
        output.format = OutputFormat::Json;
    }

    // JSON output uses a stable, camelCase projection matching the reference
    // CLI (rather than the internal snake_case model shape).
    if output.format == OutputFormat::Json {
        // Under --strict, warnings are promoted to errors for the exit code.
        let final_findings: Vec<Finding> = if output.strict {
            findings
                .iter()
                .cloned()
                .map(|mut f| {
                    if f.severity == crate::models::Severity::Warning {
                        f.severity = crate::models::Severity::Error;
                    }
                    f
                })
                .collect()
        } else {
            findings.clone()
        };
        let exit = crate::core::exit_codes::audit_exit_code(&crate::models::ExitContext {
            findings: final_findings.clone(),
            strict: output.strict,
        });
        let json = render_scan_json(&root, &final_findings, &summary, exit);
        if let Some(path) = &output.output {
            std::fs::write(path, json + "\n")?;
        } else {
            println!("{json}");
        }
        return Ok(exit);
    }

    crate::commands::shared::output_findings_verbose(
        &root,
        &output,
        &findings,
        &summary,
        args.verbose,
    )
}

/// Render the scan result as the reference CLI's JSON shape.
fn render_scan_json(
    root: &Utf8PathBuf,
    findings: &[Finding],
    summary: &crate::models::AuditSummary,
    exit_code: u8,
) -> String {
    let findings_json: Vec<serde_json::Value> = findings
        .iter()
        .map(|f| {
            let locations: Vec<serde_json::Value> = f
                .locations
                .iter()
                .map(|o| {
                    let mut loc = serde_json::Map::new();
                    loc.insert("file".to_string(), serde_json::json!(display_path(root, &o.file_path)));
                    if let Some(line) = o.line {
                        loc.insert("line".to_string(), serde_json::json!(line));
                    }
                    loc.insert("kind".to_string(), serde_json::json!(o.kind.as_str()));
                    serde_json::Value::Object(loc)
                })
                .collect();
            serde_json::json!({
                "id": f.id,
                "ruleId": f.rule_id,
                "severity": f.severity.as_str(),
                "variable": f.variable,
                "message": f.message,
                "locations": locations,
            })
        })
        .collect();

    let value = serde_json::json!({
        "exitCode": exit_code,
        "summary": {
            "filesScanned": summary.files_scanned,
            "variablesFound": summary.variables_found,
            "errors": summary.errors,
            "warnings": summary.warnings,
            "infos": summary.infos,
            "total": summary.total,
        },
        "findings": findings_json,
    });
    serde_json::to_string_pretty(&value).unwrap_or_default()
}

/// Display path relative to root (best-effort), used for stable fingerprints.
fn display_path(root: &Utf8PathBuf, path: &Utf8PathBuf) -> String {
    path.strip_prefix(root)
        .map(|p| p.to_string())
        .unwrap_or_else(|_| path.to_string())
}

#[derive(serde::Serialize, serde::Deserialize)]
struct BaselineEntry {
    rule_id: String,
    variable: String,
    files: Vec<String>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct BaselineFile {
    version: u32,
    findings: Vec<BaselineEntry>,
}

fn fingerprint(root: &Utf8PathBuf, finding: &Finding) -> BaselineEntry {
    let mut files: Vec<String> = finding
        .locations
        .iter()
        .map(|o| display_path(root, &o.file_path))
        .collect();
    files.sort();
    files.dedup();
    BaselineEntry {
        rule_id: finding.rule_id.clone(),
        variable: finding.variable.clone(),
        files,
    }
}

fn entry_matches(a: &BaselineEntry, b: &BaselineEntry) -> bool {
    a.rule_id == b.rule_id && a.variable == b.variable && a.files == b.files
}

fn apply_baseline(findings: Vec<Finding>, root: &Utf8PathBuf, baseline_path: &Utf8PathBuf) -> Vec<Finding> {
    let full = root.join(baseline_path);
    let baseline: BaselineFile = match std::fs::read_to_string(&full)
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
    {
        Some(b) => b,
        None => {
            eprintln!("warning Could not read baseline {baseline_path}");
            return findings;
        }
    };

    let before = findings.len();
    let kept: Vec<Finding> = findings
        .into_iter()
        .filter(|f| {
            let fp = fingerprint(root, f);
            !baseline.findings.iter().any(|b| entry_matches(b, &fp))
        })
        .collect();
    let suppressed = before - kept.len();
    if suppressed > 0 {
        eprintln!(
            "info {} finding{} suppressed by baseline",
            suppressed,
            if suppressed == 1 { "" } else { "s" }
        );
    }
    kept
}

fn write_baseline(findings: &[Finding], root: &Utf8PathBuf, baseline_path: &Utf8PathBuf) -> Result<(), anyhow::Error> {
    let full = root.join(baseline_path);
    let baseline = BaselineFile {
        version: 1,
        findings: findings.iter().map(|f| fingerprint(root, f)).collect(),
    };
    if let Some(parent) = full.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&full, serde_json::to_string_pretty(&baseline)? + "\n")?;
    eprintln!("info Wrote baseline to {baseline_path}");
    Ok(())
}
