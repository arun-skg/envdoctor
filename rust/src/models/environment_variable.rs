use serde::{Deserialize, Serialize};
use crate::models::{Origin, VariableType};

/// A normalized view of one environment variable across every file in the
/// project. A single `EnvironmentVariable` aggregates every origin (definition,
/// reference, or usage) that mentions `name`.
///
/// `value` is only ever set for definitions and is an implementation detail:
/// it is never rendered in CLI output and never written into generated files.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnvironmentVariable {
    pub name: String,
    /// Raw value, present when at least one origin is a definition with a value.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    /// True when the name matches the secret heuristic.
    pub is_secret: bool,
    /// Inferred from `value` when available, else "unknown".
    #[serde(rename = "type")]
    pub var_type: VariableType,
    /// Every place this name was observed.
    pub origins: Vec<Origin>,
    /**
     * Rule ids that should be ignored for this variable, declared inline in the
     * env file via `# envdoctor:ignore <rule>` comments.
     */
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ignore_rules: Option<Vec<String>>,
}

impl EnvironmentVariable {
    /// Check if a name looks like a secret based on common patterns.
    pub fn is_secret_name(name: &str) -> bool {
        regex::Regex::new(r"(?i)(SECRET|TOKEN|PASSWORD|PASS|API[_A-Z]*KEY|PRIVATE[_-]?KEY|CREDENTIALS)")
            .unwrap()
            .is_match(name)
    }

    /// Build a normalized variable from a name, optional value, and origins.
    pub fn create(name: String, value: Option<String>, origins: Vec<Origin>, ignore_rules: Option<Vec<String>>) -> Self {
        let is_secret = Self::is_secret_name(&name);
        let var_type = crate::utils::type_infer::infer_type(value.as_deref());
        Self {
            name,
            value,
            is_secret,
            var_type,
            origins,
            ignore_rules,
        }
    }

    /// Merge multiple variables with the same name into one, preserving every
    /// origin and preferring the first non-empty value. Used by parsers to flatten
    /// repeated references into a single variable.
    pub fn merge(variables: Vec<Self>) -> Vec<Self> {
        use std::collections::HashMap;
        let mut by_name: HashMap<String, Self> = HashMap::new();

        for v in variables {
            if let Some(existing) = by_name.get_mut(&v.name) {
                existing.origins.extend(v.origins);
                if existing.value.is_none() && v.value.is_some() {
                    existing.value = v.value.clone();
                    existing.var_type = crate::utils::type_infer::infer_type(v.value.as_deref());
                    existing.is_secret = Self::is_secret_name(&v.name);
                }
            } else {
                by_name.insert(v.name.clone(), v);
            }
        }

        by_name.into_values().collect()
    }
}