use crate::config::EnvdoctorConfig;
use crate::detectors::{Detector, IndexedModel};
use crate::models::{Finding, Origin, ProjectModel, Severity};
use crate::utils::glob::{matches_any_glob, matches_glob};
use std::collections::HashMap;

/// Detector ids and their associated rules in a well-known order. The order
/// here is the order findings are produced and (roughly) the priority.
pub fn all_detectors() -> Vec<Box<dyn Detector>> {
    vec![
        Box::new(crate::detectors::MissingDetector),
        Box::new(crate::detectors::UnusedDetector),
        Box::new(crate::detectors::UndefinedSourceDetector),
        Box::new(crate::detectors::DuplicatesDetector),
        Box::new(crate::detectors::EnvironmentDiffDetector),
        Box::new(crate::detectors::TypeMismatchDetector),
        Box::new(crate::detectors::PublicPrefixDetector),
        Box::new(crate::detectors::WeakSecretDetector),
        Box::new(crate::detectors::TypoDetector),
        Box::new(crate::detectors::SchemaValidationDetector),
    ]
}

/// Run the full audit pipeline over a model and return aggregated findings.
pub fn run_audit(
    _model: &ProjectModel,
    config: &EnvdoctorConfig,
    index: &IndexedModel,
) -> Vec<Finding> {
    let mut findings: Vec<Finding> = Vec::new();
    for detector in all_detectors() {
        findings.extend(detector.detect(index));
    }

    // Apply per-rule severity overrides first.
    findings = apply_rule_severities(findings, config);

    // Remove findings for explicitly ignored variable names.
    findings = apply_ignores(findings, config);

    findings
}

/// Apply user-configured severity overrides for each rule. "off" removes the
/// finding entirely, "error"/"warning" rewrite its severity.
fn apply_rule_severities(findings: Vec<Finding>, config: &EnvdoctorConfig) -> Vec<Finding> {
    findings
        .into_iter()
        .filter_map(|f| {
            let override_sev = config.rules.get(&f.rule_id);
            match override_sev {
                Some(crate::config::RuleSeverity::Off) => None,
                Some(crate::config::RuleSeverity::Error) => {
                    Some(Finding { severity: Severity::Error, ..f })
                }
                Some(crate::config::RuleSeverity::Warning) => {
                    Some(Finding { severity: Severity::Warning, ..f })
                }
                None => Some(f),
            }
        })
        .collect()
}

/// Drop findings whose variable matches any `ignore_variables` glob.
fn apply_ignores(findings: Vec<Finding>, config: &EnvdoctorConfig) -> Vec<Finding> {
    if config.ignore_variables.is_empty() {
        return findings;
    }
    findings
        .into_iter()
        .filter(|f| !matches_any_glob(&config.ignore_variables, &f.variable))
        .collect()
}

/// Helper: is `name` defined in any dotenv file?
pub fn is_defined_in_any_env(index: &IndexedModel, name: &str) -> bool {
    index.env_definitions.contains_key(name)
}

/// Helper: is `name` documented in `.env.example`?
pub fn is_documented(index: &IndexedModel, name: &str) -> bool {
    index.example_names.contains(name)
}

/// Build the `rule_id -> override severity` map for convenient lookups.
#[allow(dead_code)]
pub fn rule_severity_map(config: &EnvdoctorConfig) -> HashMap<String, crate::config::RuleSeverity> {
    config.rules.clone()
}

/// Test helper to check whether a name matches a single ignore glob.
#[allow(dead_code)]
pub fn is_ignored(name: &str, patterns: &[String]) -> bool {
    patterns.iter().any(|p| matches_glob(name, p))
}

/// Flatten all origins for a name from a model (used by detectors needing
/// cross-format locations).
#[allow(dead_code)]
pub fn locations_for(model: &ProjectModel, name: &str) -> Vec<Origin> {
    model.origins_for_name(name)
}
