use crate::detectors::{Definition, Detector, IndexedModel, def_sort_key, make_finding};
use crate::models::{Finding, Severity};
use std::sync::LazyLock;

static BLOCKLIST: LazyLock<std::collections::HashSet<String>> = LazyLock::new(|| {
    [
        "",
        "changeme",
        "password",
        "password123",
        "secret",
        "secret123",
        "token",
        "key",
        "apikey",
        "api_key",
        "test",
        "testing",
        "12345678",
        "123456789",
        "your_secret",
        "your_token",
        "your_api_key",
        "your_password",
        "example",
        "dummy",
        "foo",
        "bar",
        "admin",
        "default",
        "null",
        "undefined",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
});

fn is_weak_secret(_name: &str, value: Option<&str>) -> bool {
    let Some(value) = value else {
        return false;
    };
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return false;
    }
    if BLOCKLIST.contains(&trimmed.to_lowercase()) {
        return true;
    }
    if trimmed.len() < 8 {
        return true;
    }
    false
}

/// Weak/placeholder secret detector.
///
/// Secret-like variables in real env files should not use obvious placeholder
/// values. This detector only inspects definitions in actual environment files,
/// never `.env.example`.
pub struct WeakSecretDetector;

impl Detector for WeakSecretDetector {
    fn id(&self) -> &'static str {
        "weak-secret"
    }

    fn name(&self) -> &'static str {
        "weak-secret"
    }

    fn description(&self) -> &'static str {
        "A secret-looking variable in an environment file has a weak or placeholder value."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();

        let mut entries: Vec<(&String, &Vec<Definition>)> = index.env_definitions.iter().collect();
        entries.sort_by(|(na, da), (nb, db)| def_sort_key(da).cmp(&def_sort_key(db)).then(na.cmp(nb)));

        for (name, defs) in entries {
            for def in defs {
                if !def.is_secret {
                    continue;
                }
                if !is_weak_secret(name, def.value.as_deref()) {
                    continue;
                }
                let location = match def.origin.line {
                    Some(line) => format!("{}:{}", def.origin.file_path, line),
                    None => def.origin.file_path.to_string(),
                };
                findings.push(make_finding(
                    "weak-secret",
                    Severity::Warning,
                    name,
                    format!("{} has a weak or placeholder value in {}", name, location),
                    vec![def.origin.clone()],
                ));
            }
        }

        findings
    }
}