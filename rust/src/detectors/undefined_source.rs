use crate::detectors::{Detector, IndexedModel, make_finding, origin_sort_key};
use crate::models::{Finding, Origin, Severity};

/// Undefined-in-source: a variable referenced as `process.env.X` /
/// `import.meta.env.X` in source code that is not defined in any environment
/// file and not documented in `.env.example`. These are the most dangerous
/// findings — code that will silently read `undefined` at runtime.
pub struct UndefinedSourceDetector;

impl Detector for UndefinedSourceDetector {
    fn id(&self) -> &'static str {
        "undefined-in-source"
    }

    fn name(&self) -> &'static str {
        "undefined-in-source"
    }

    fn description(&self) -> &'static str {
        "Used in source code but not defined in any environment file and not documented in .env.example."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();
        let defined: std::collections::HashSet<&String> = index.env_definitions.keys().collect();

        let mut entries: Vec<(&String, &Vec<Origin>)> = index.source_usages.iter().collect();
        entries.sort_by(|(na, oa), (nb, ob)| origin_sort_key(oa).cmp(&origin_sort_key(ob)).then(na.cmp(nb)));

        for (name, origins) in entries {
            if defined.contains(name) {
                continue;
            }
            findings.push(make_finding(
                "undefined-in-source",
                Severity::Error,
                name,
                "used in source code but not defined in any environment file".to_string(),
                origins.clone(),
            ));
        }

        findings
    }
}