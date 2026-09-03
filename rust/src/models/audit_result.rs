use serde::{Deserialize, Serialize};
use crate::models::Origin;

/// A single problem found by a detector. `message` is written for humans and
/// must never contain a variable value.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Finding {
    /// Stable id, e.g. `missing.DATABASE_URL` or `type-mismatch.PORT`.
    pub id: String,
    /// Detector id that produced this finding.
    pub rule_id: String,
    pub severity: Severity,
    pub variable: String,
    pub message: String,
    /// Where the variable was seen; rendered as `path:line`.
    pub locations: Vec<Origin>,
}

impl Finding {
    pub fn new(rule_id: &str, severity: Severity, variable: &str, message: String, locations: Vec<Origin>) -> Self {
        Self {
            id: format!("{}.{}", rule_id, variable),
            rule_id: rule_id.to_string(),
            severity,
            variable: variable.to_string(),
            message,
            locations,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Error,
    Warning,
    Info,
}

impl Severity {
    pub fn as_str(&self) -> &'static str {
        match self {
            Severity::Error => "error",
            Severity::Warning => "warning",
            Severity::Info => "info",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuditSummary {
    pub files_scanned: usize,
    pub variables_found: usize,
    pub errors: usize,
    pub warnings: usize,
    pub infos: usize,
    pub total: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuditResult {
    pub findings: Vec<Finding>,
    pub summary: AuditSummary,
    /// 0 = clean, 1 = errors, (2 is reserved for usage/config errors).
    pub exit_code: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExitContext {
    pub findings: Vec<Finding>,
    pub strict: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuditFailureKind {
    None,
    Errors,
    Warnings,
    UsageError,
}