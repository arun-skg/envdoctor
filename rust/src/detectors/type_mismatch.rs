use crate::detectors::{Definition, Detector, IndexedModel, def_sort_key, make_finding};
use crate::models::{Finding, Severity, VariableType};
use std::collections::HashMap;

/// Type mismatch: the same variable is defined with values of incompatible
/// inferred types across environment files (e.g. `PORT=3000` in development
/// but `PORT=3000abc` in production). The "expected" type is taken from the
/// development file when present, otherwise the most common type. Only
/// variable *types* and locations are reported — never values.
pub struct TypeMismatchDetector;

impl Detector for TypeMismatchDetector {
    fn id(&self) -> &'static str {
        "type-mismatch"
    }

    fn name(&self) -> &'static str {
        "type-mismatch"
    }

    fn description(&self) -> &'static str {
        "The same variable has incompatible inferred types across environment files."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();

        let mut entries: Vec<(&String, &Vec<Definition>)> = index.env_definitions.iter().collect();
        entries.sort_by(|(na, da), (nb, db)| def_sort_key(da).cmp(&def_sort_key(db)).then(na.cmp(nb)));

        for (name, defs) in entries {
            let typed: Vec<&crate::detectors::Definition> = defs
                .iter()
                .filter(|d| d.value.is_some() && d.var_type != VariableType::Unknown && !d.value.as_ref().unwrap().is_empty())
                .collect();
            if typed.len() < 2 {
                continue;
            }

            let distinct_types: std::collections::HashSet<_> = typed.iter().map(|d| d.var_type).collect();
            if distinct_types.len() < 2 {
                continue;
            }

            let expected = typed
                .iter()
                .find(|d| d.environment.as_deref() == Some("development"))
                .map(|d| d.var_type)
                .unwrap_or_else(|| most_common_type(&typed));

            for def in typed {
                if def.var_type == expected {
                    continue;
                }
                findings.push(make_finding(
                    "type-mismatch",
                    Severity::Error,
                    name,
                    format!("expected: {}, found: {}", expected, def.var_type),
                    vec![def.origin.clone()],
                ));
            }
        }

        findings
    }
}

fn most_common_type(defs: &[&crate::detectors::Definition]) -> VariableType {
    // Count occurrences but resolve ties by first-seen order, matching the
    // reference CLI which iterates its insertion-ordered `Map`.
    let mut counts: HashMap<VariableType, usize> = HashMap::new();
    let mut order: Vec<VariableType> = Vec::new();
    for d in defs {
        if !counts.contains_key(&d.var_type) {
            order.push(d.var_type);
        }
        *counts.entry(d.var_type).or_default() += 1;
    }
    let mut best = order[0];
    let mut best_count = 0;
    for ty in order {
        let count = counts[&ty];
        if count > best_count {
            best = ty;
            best_count = count;
        }
    }
    best
}