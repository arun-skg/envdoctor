use crate::detectors::{Definition, Detector, IndexedModel, def_sort_key, make_finding};
use crate::models::{Finding, Severity, Origin};
use std::collections::HashSet;

/// Unused: a variable defined in an environment file that is never referenced
/// anywhere — not in source code, not in docker-compose, not in GitHub Actions.
/// `.env.example` contents are documentation and are excluded here.
pub struct UnusedDetector;

impl Detector for UnusedDetector {
    fn id(&self) -> &'static str {
        "unused"
    }

    fn name(&self) -> &'static str {
        "unused"
    }

    fn description(&self) -> &'static str {
        "Defined in an environment file but never referenced in source, docker-compose, GitHub Actions, or Kubernetes manifests."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();
        let mut used: HashSet<&String> = index.usages.keys().collect();
        for name in index.compose_definitions.keys() { used.insert(name); }
        for name in index.action_definitions.keys() { used.insert(name); }
        for name in index.k8s_definitions.keys() { used.insert(name); }

        // Iterate in a stable file/line order so output is deterministic and
        // matches the reference CLI (which iterates env definitions in the
        // order they were parsed).
        let mut entries: Vec<(&String, &Vec<Definition>)> =
            index.env_definitions.iter().collect();
        entries.sort_by(|(na, da), (nb, db)| {
            def_sort_key(da).cmp(&def_sort_key(db)).then(na.cmp(nb))
        });

        let mut seen = HashSet::new();

        for (name, defs) in entries {
            if !seen.insert(name.clone()) {
                continue;
            }
            if used.contains(name) {
                continue;
            }
            let origins: Vec<Origin> = defs.iter().map(|d| d.origin.clone()).collect();
            findings.push(make_finding(
                "unused",
                Severity::Warning,
                name,
                "defined but never referenced".to_string(),
                origins,
            ));
        }

        findings
    }
}