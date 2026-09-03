use crate::detectors::{Detector, IndexedModel, make_finding};
use crate::models::{Finding, Origin, Severity};
use std::collections::HashMap;

/// Duplicates: the same variable defined more than once within a single file.
/// dotenv applies last-wins, so a repeated key is a silent override that
/// usually means a merge conflict or a copy-paste bug. (Distinct values across
/// *different* environment files are expected and not flagged here.)
pub struct DuplicatesDetector;

impl Detector for DuplicatesDetector {
    fn id(&self) -> &'static str {
        "duplicates"
    }

    fn name(&self) -> &'static str {
        "duplicates"
    }

    fn description(&self) -> &'static str {
        "The same variable is defined more than once in a single file."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();

        for file in &index.model.env_files {
            let mut by_name: HashMap<String, Vec<Origin>> = HashMap::new();
            // Track first-seen order so output matches the reference CLI, which
            // iterates its per-file `Map` in insertion (variable) order.
            let mut order: Vec<String> = Vec::new();
            for v in &file.variables {
                if !by_name.contains_key(&v.name) {
                    order.push(v.name.clone());
                }
                let entry = by_name.entry(v.name.clone()).or_default();
                entry.extend(v.origins.iter().cloned());
            }

            for name in order {
                let origins = by_name.remove(&name).unwrap_or_default();
                if origins.len() < 2 {
                    continue;
                }
                let lines: Vec<usize> = origins.iter().filter_map(|o| o.line).collect();
                let where_str = if !lines.is_empty() {
                    format!("on lines {}", lines.iter().map(|l| l.to_string()).collect::<Vec<_>>().join(", "))
                } else {
                    "in this file".to_string()
                };
                findings.push(make_finding(
                    "duplicates",
                    Severity::Error,
                    &name,
                    format!("defined {} times {}", origins.len(), where_str),
                    origins,
                ));
            }
        }

        findings
    }
}