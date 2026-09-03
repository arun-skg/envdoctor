use crate::models::{Finding, Origin, ProjectModel, VariableType};
use std::collections::HashMap;

/// A concrete definition of a variable in one file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Definition {
    pub name: String,
    pub value: Option<String>,
    pub var_type: VariableType,
    pub is_secret: bool,
    pub environment: Option<String>,
    pub origin: Origin,
}

/// The format-agnostic view detectors operate on. Built once by `build_index`
/// so detectors never scan raw files and never repeat the same work.
#[derive(Debug, Clone)]
pub struct IndexedModel {
    pub model: ProjectModel,
    /// Every definition found in dotenv files, keyed by name (duplicates kept).
    pub env_definitions: HashMap<String, Vec<Definition>>,
    /// Definitions found in docker-compose files, keyed by name.
    pub compose_definitions: HashMap<String, Vec<Definition>>,
    /// Definitions found in GitHub Actions workflows, keyed by name.
    pub action_definitions: HashMap<String, Vec<Definition>>,
    /// Definitions found in Kubernetes manifests, keyed by name.
    pub k8s_definitions: HashMap<String, Vec<Definition>>,
    /// Every usage (source, compose, actions, k8s), keyed by name.
    pub usages: HashMap<String, Vec<Origin>>,
    /// Usages that come specifically from source code.
    pub source_usages: HashMap<String, Vec<Origin>>,
    /// Names documented in `.env.example`.
    pub example_names: std::collections::HashSet<String>,
    /// Distinct environment labels among dotenv files (excluding "example").
    pub env_labels: Vec<String>,
}

/// Stable ordering key for a set of definitions: the earliest (file, line)
/// they were declared at. Matches the reference CLI's parse-order emission,
/// where `Map`s are iterated in insertion order (file path then line number).
pub(crate) fn def_sort_key(defs: &[Definition]) -> (String, usize) {
    defs.iter()
        .map(|d| origin_key(&d.origin))
        .min()
        .unwrap_or_default()
}

/// Stable ordering key for a set of origins: the earliest (file, line).
pub(crate) fn origin_sort_key(origins: &[Origin]) -> (String, usize) {
    origins.iter().map(origin_key).min().unwrap_or_default()
}

fn origin_key(o: &Origin) -> (String, usize) {
    (o.file_path.to_string(), o.line.unwrap_or(usize::MAX))
}

pub trait Detector: Send + Sync {
    fn id(&self) -> &'static str;
    fn name(&self) -> &'static str;
    fn description(&self) -> &'static str;
    fn detect(&self, index: &IndexedModel) -> Vec<Finding>;
}

/// Helper to create a finding with a stable id.
pub fn make_finding(
    rule_id: &str,
    severity: crate::models::Severity,
    variable: &str,
    message: String,
    locations: Vec<Origin>,
) -> Finding {
    Finding::new(rule_id, severity, variable, message, locations)
}