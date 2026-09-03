use crate::detectors::{Detector, IndexedModel, make_finding};
use crate::models::{Finding, ProjectModel, Severity};
use std::collections::{BTreeSet, HashSet};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnvDiffEntry {
    pub name: String,
    pub present_in_both: bool,
    pub present_in_a: bool,
    pub present_in_b: bool,
}

/// The set of variable names defined for a given environment label.
pub fn variables_for_environment(model: &ProjectModel, label: &str) -> HashSet<String> {
    let mut names = HashSet::new();
    for file in &model.env_files {
        if file.environment.as_deref() == Some(label) {
            for v in &file.variables {
                names.insert(v.name.clone());
            }
        }
    }
    names
}

/// Compare two environment labels, returning one entry per variable.
pub fn compare_environments(
    model: &ProjectModel,
    label_a: &str,
    label_b: &str,
) -> Vec<EnvDiffEntry> {
    let a = variables_for_environment(model, label_a);
    let b = variables_for_environment(model, label_b);
    let all: BTreeSet<String> = a.iter().cloned().chain(b.iter().cloned()).collect();

    let mut entries = Vec::new();
    for name in all {
        let present_in_a = a.contains(&name);
        let present_in_b = b.contains(&name);
        entries.push(EnvDiffEntry {
            name,
            present_in_both: present_in_a && present_in_b,
            present_in_a,
            present_in_b,
        });
    }
    entries.sort_by(|x, y| x.name.cmp(&y.name));
    entries
}

pub struct EnvironmentDiffDetector;

impl Detector for EnvironmentDiffDetector {
    fn id(&self) -> &'static str {
        "environment-diff"
    }

    fn name(&self) -> &'static str {
        "environment-diff"
    }

    fn description(&self) -> &'static str {
        "A variable exists in one environment file but is missing from another."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();
        let labels = &index.env_labels;
        if labels.len() < 2 {
            return findings;
        }
        let reference = if labels.iter().any(|l| l == "development") {
            "development"
        } else {
            labels[0].as_str()
        };

        for other in labels {
            if other == reference {
                continue;
            }
            for entry in compare_environments(&index.model, reference, other) {
                if entry.present_in_both {
                    continue;
                }
                let missing_in = if entry.present_in_a { other } else { reference };
                findings.push(make_finding(
                    "environment-diff",
                    Severity::Warning,
                    &entry.name,
                    format!("{} → {} · {} missing in {}", reference, other, entry.name, missing_in),
                    vec![],
                ));
            }
        }

        findings
    }
}