use crate::core::audit::all_detectors;
use crate::models::{Finding, Severity};
use serde_json::{json, Value};

const SARIF_SCHEMA: &str =
    "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json";

/// Detectors whose default severity is `error`; everything else defaults to
/// `warning`. Mirrors the reference `defaultLevelForDetector`.
const ERROR_DETECTORS: &[&str] = &["missing", "undefined-in-source", "type-mismatch", "public-prefix"];

/// Render findings as SARIF 2.1.0 for GitHub code scanning.
pub fn render_sarif(findings: &[Finding], root_dir: &camino::Utf8PathBuf) -> String {
    let results: Vec<Value> = findings.iter().map(|f| finding_to_sarif(f, root_dir)).collect();

    let sarif = json!({
        "$schema": SARIF_SCHEMA,
        "version": "2.1.0",
        "runs": [{
            "tool": {
                "driver": {
                    "name": "envdoctor",
                    "informationUri": "https://github.com/arun-skg/envdoctor",
                    "rules": render_rules(),
                }
            },
            "results": results,
        }]
    });

    serde_json::to_string_pretty(&sarif).unwrap()
}

fn severity_to_level(severity: Severity) -> &'static str {
    match severity {
        Severity::Error => "error",
        Severity::Warning => "warning",
        Severity::Info => "note",
    }
}

fn finding_to_sarif(f: &Finding, root_dir: &camino::Utf8PathBuf) -> Value {
    let locations: Vec<Value> = f
        .locations
        .iter()
        .map(|o| {
            let rel = o
                .file_path
                .strip_prefix(root_dir)
                .ok()
                .map(|p: &camino::Utf8Path| p.as_str())
                .unwrap_or(o.file_path.as_str());

            let mut physical = serde_json::Map::new();
            physical.insert(
                "artifactLocation".to_string(),
                json!({ "uri": rel.replace('\\', "/") }),
            );
            if let Some(l) = o.line {
                if l > 0 {
                    physical.insert("region".to_string(), json!({ "startLine": l }));
                }
            }
            json!({ "physicalLocation": Value::Object(physical) })
        })
        .collect();

    json!({
        "ruleId": f.rule_id,
        "level": severity_to_level(f.severity),
        "message": { "text": format!("{}: {}", f.variable, f.message) },
        "locations": locations,
    })
}

/// The full detector catalog, matching the reference CLI (all rules appear,
/// not only the ones with findings).
fn render_rules() -> Vec<Value> {
    all_detectors()
        .iter()
        .map(|d| {
            let level = if ERROR_DETECTORS.contains(&d.id()) {
                "error"
            } else {
                "warning"
            };
            json!({
                "id": d.id(),
                "name": d.name(),
                "shortDescription": { "text": d.description() },
                "defaultConfiguration": { "level": level },
            })
        })
        .collect()
}
