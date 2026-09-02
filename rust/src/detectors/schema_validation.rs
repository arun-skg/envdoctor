use crate::detectors::{Definition, Detector, IndexedModel, def_sort_key, make_finding};
use crate::models::{Finding, Severity};
use crate::config::{VariableSchema, SchemaType};
use regex::Regex;

/// Build a validator for a variable schema.
fn build_validator(schema: &VariableSchema) -> Option<Box<dyn Fn(&str) -> Result<(), String> + '_>> {
    if let Some(enum_values) = &schema.enum_values {
        if !enum_values.is_empty() {
            let enum_values = enum_values.clone();
            return Some(Box::new(move |v: &str| {
                if enum_values.contains(&v.to_string()) {
                    Ok(())
                } else {
                    Err(format!("must be one of: {}", enum_values.join(", ")))
                }
            }));
        }
    }

    match schema.var_type {
        Some(SchemaType::Integer) => {
            let min = schema.min;
            let max = schema.max;
            Some(Box::new(move |v: &str| {
                match v.parse::<i64>() {
                    Ok(n) => {
                        if let Some(min) = min {
                            if n < min { return Err(format!("must be >= {}", min)); }
                        }
                        if let Some(max) = max {
                            if n > max { return Err(format!("must be <= {}", max)); }
                        }
                        Ok(())
                    }
                    Err(_) => Err("must be an integer".to_string()),
                }
            }))
        }
        Some(SchemaType::Float) => {
            let min = schema.min;
            let max = schema.max;
            Some(Box::new(move |v: &str| {
                match v.parse::<f64>() {
                    Ok(n) => {
                        if let Some(min) = min {
                            if n < min as f64 { return Err(format!("must be >= {}", min)); }
                        }
                        if let Some(max) = max {
                            if n > max as f64 { return Err(format!("must be <= {}", max)); }
                        }
                        Ok(())
                    }
                    Err(_) => Err("must be a float".to_string()),
                }
            }))
        }
        Some(SchemaType::Boolean) => Some(Box::new(|v: &str| {
            match v.parse::<bool>() {
                Ok(_) => Ok(()),
                Err(_) => Err("must be a boolean".to_string()),
            }
        })),
        Some(SchemaType::Url) => Some(Box::new(|v: &str| {
            if v.starts_with("http://") || v.starts_with("https://") {
                Ok(())
            } else {
                Err("must be a valid URL".to_string())
            }
        })),
        Some(SchemaType::Json) => Some(Box::new(|v: &str| {
            match serde_json::from_str::<serde_json::Value>(v) {
                Ok(_) => Ok(()),
                Err(_) => Err("must be valid JSON".to_string()),
            }
        })),
        Some(SchemaType::Regex) => {
            if let Some(regex_str) = &schema.regex {
                match Regex::new(regex_str) {
                    Ok(re) => Some(Box::new(move |v: &str| {
                        if re.is_match(v) {
                            Ok(())
                        } else {
                            Err(format!("must match {}", regex_str))
                        }
                    })),
                    Err(_) => None,
                }
            } else {
                None
            }
        }
        Some(SchemaType::String) | Some(SchemaType::Enum) | None => Some(Box::new(|_v: &str| Ok(()))),
    }
}

fn validate_value(value: Option<&str>, schema: &VariableSchema) -> Result<(), String> {
    if value.is_none() || value.unwrap().trim().is_empty() {
        if schema.optional.unwrap_or(false) {
            return Ok(());
        }
        return Err("value is required".to_string());
    }

    let validator = build_validator(schema);
    let Some(validator) = validator else {
        return Ok(());
    };

    validator(value.unwrap())
}

/// A variable value does not match its declared schema.
pub struct SchemaValidationDetector;

impl Detector for SchemaValidationDetector {
    fn id(&self) -> &'static str {
        "schema-validation"
    }

    fn name(&self) -> &'static str {
        "schema-validation"
    }

    fn description(&self) -> &'static str {
        "A variable value does not match its declared schema."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let schema = &index.model.config.schema;
        if schema.is_empty() {
            return vec![];
        }

        let mut findings = Vec::new();

        let mut entries: Vec<(&String, &Vec<Definition>)> = index.env_definitions.iter().collect();
        entries.sort_by(|(na, da), (nb, db)| def_sort_key(da).cmp(&def_sort_key(db)).then(na.cmp(nb)));

        for (name, defs) in entries {
            let Some(variable_schema) = schema.get(name) else {
                continue;
            };

            for def in defs {
                let result = validate_value(def.value.as_deref(), variable_schema);
                if result.is_ok() {
                    continue;
                }
                findings.push(make_finding(
                    "schema-validation",
                    Severity::Error,
                    name,
                    format!("does not match schema: {}", result.unwrap_err()),
                    vec![def.origin.clone()],
                ));
            }
        }

        findings
    }
}