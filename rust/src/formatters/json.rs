use crate::models::{AuditResult, AuditSummary, Finding};
use serde_json::{json, Value};

/// Render findings as JSON matching the TS output format.
pub fn render_json(findings: &[Finding], summary: &AuditSummary) -> String {
    let output = json!({
        "findings": findings.iter().map(finding_to_json).collect::<Vec<_>>(),
        "summary": {
            "filesScanned": summary.files_scanned,
            "variablesFound": summary.variables_found,
            "errors": summary.errors,
            "warnings": summary.warnings,
            "infos": summary.infos,
            "total": summary.total,
        },
        "exitCode": if summary.errors > 0 { 1 } else { 0 }
    });

    serde_json::to_string_pretty(&output).unwrap()
}

fn finding_to_json(f: &Finding) -> Value {
    json!({
        "id": f.id,
        "ruleId": f.rule_id,
        "severity": f.severity.as_str(),
        "variable": f.variable,
        "message": f.message,
        "locations": f.locations.iter().map(|o| json!({
            "file": o.file_path.as_str(),
            "line": o.line,
            "kind": format!("{:?}", o.kind).to_lowercase(),
            "environment": o.environment,
            "format": o.format.as_ref().map(|f| format!("{:?}", f).to_lowercase()),
            "subkind": o.subkind,
        })).collect::<Vec<_>>(),
    })
}

/// Render a complete AuditResult as JSON.
pub fn render_audit_result_json(result: &AuditResult) -> String {
    serde_json::to_string_pretty(result).unwrap()
}