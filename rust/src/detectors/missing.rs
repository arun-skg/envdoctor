use crate::detectors::{Definition, Detector, IndexedModel, def_sort_key, make_finding, origin_sort_key};
use crate::models::{Finding, Origin, Severity};
use std::collections::HashSet;

/// Missing: a variable that is referenced (in docker-compose, GitHub Actions,
/// or `.env.example`) but defined in no environment file. Source-code
/// references are the concern of the `undefined-in-source` detector.
pub struct MissingDetector;

impl Detector for MissingDetector {
    fn id(&self) -> &'static str {
        "missing"
    }

    fn name(&self) -> &'static str {
        "missing"
    }

    fn description(&self) -> &'static str {
        "Referenced in docker-compose, GitHub Actions, or .env.example but not defined in any environment file."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();
        let defined: HashSet<&String> = index.env_definitions.keys().collect();
        let source_used: HashSet<&String> = index.source_usages.keys().collect();
        let mut seen = HashSet::new();

        // Built in the same three phases as the reference CLI (compose defs,
        // then .env.example names, then compose `${VAR}` interpolations) so the
        // emission order matches. Each HashMap phase is sorted by parse order.
        let mut referenced: Vec<(String, Vec<Origin>)> = Vec::new();

        // Compose definitions that are NOT in any .env file are "missing".
        let mut compose_entries: Vec<(&String, &Vec<Definition>)> =
            index.compose_definitions.iter().collect();
        compose_entries
            .sort_by(|(na, da), (nb, db)| def_sort_key(da).cmp(&def_sort_key(db)).then(na.cmp(nb)));
        for (name, defs) in compose_entries {
            if !defined.contains(name) && !source_used.contains(name) {
                let origins: Vec<Origin> = defs.iter().map(|d| d.origin.clone()).collect();
                referenced.push((name.clone(), origins));
            }
        }

        // .env.example names that are NOT in any .env file are "missing".
        // Iterate the model's example files directly so the order matches the
        // reference CLI's `exampleNames` set (populated in parse order).
        for file in &index.model.env_files {
            if file.environment.as_deref() != Some("example") {
                continue;
            }
            for v in &file.variables {
                if !defined.contains(&v.name) && !source_used.contains(&v.name) {
                    referenced.push((v.name.clone(), Vec::new()));
                }
            }
        }

        // `${VAR}` interpolation in docker-compose means compose expects the
        // variable to exist. GitHub Actions `secrets.X`/`vars.X` references are
        // intentionally NOT checked here — those live in repo settings, not .env.
        let mut usage_entries: Vec<(&String, &Vec<Origin>)> = index.usages.iter().collect();
        usage_entries
            .sort_by(|(na, oa), (nb, ob)| origin_sort_key(oa).cmp(&origin_sort_key(ob)).then(na.cmp(nb)));
        for (name, origins) in usage_entries {
            let compose_origins: Vec<Origin> = origins
                .iter()
                .filter(|o| o.format == Some(crate::models::OriginFormat::DockerCompose))
                .cloned()
                .collect();
            if compose_origins.is_empty() {
                continue;
            }
            if defined.contains(name) || source_used.contains(name) {
                continue;
            }
            referenced.push((name.clone(), compose_origins));
        }

        for (name, origins) in referenced {
            if seen.insert(name.clone()) {
                findings.push(make_finding(
                    "missing",
                    Severity::Error,
                    &name,
                    "referenced but not defined in any environment file".to_string(),
                    origins,
                ));
            }
        }

        findings
    }
}