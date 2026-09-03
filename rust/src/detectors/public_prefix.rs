use crate::detectors::{Definition, Detector, IndexedModel, def_sort_key, make_finding};
use crate::models::{EnvironmentVariable, Finding, Severity};

const PUBLIC_PREFIXES: &[&str] = &[
    "NEXT_PUBLIC_",
    "VITE_",
    "PUBLIC_",
    "REACT_APP_",
    "GATSBY_",
    "EXPO_PUBLIC_",
    "NUXT_PUBLIC_",
    "ASTRO_PUBLIC_",
];

fn find_public_prefix(name: &str) -> Option<&'static str> {
    PUBLIC_PREFIXES.iter().find(|&&prefix| name.starts_with(prefix)).copied()
}

/// Public-prefix leak: variables whose names match the secret heuristic but
/// use a framework prefix that exposes them to client-side bundles.
///
/// Examples: NEXT_PUBLIC_API_KEY, VITE_JWT_SECRET, REACT_APP_PASSWORD.
pub struct PublicPrefixDetector;

impl Detector for PublicPrefixDetector {
    fn id(&self) -> &'static str {
        "public-prefix"
    }

    fn name(&self) -> &'static str {
        "public-prefix"
    }

    fn description(&self) -> &'static str {
        "A secret-looking variable uses a public framework prefix and will be exposed to client bundles."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();

        let mut entries: Vec<(&String, &Vec<Definition>)> = index.env_definitions.iter().collect();
        entries.sort_by(|(na, da), (nb, db)| def_sort_key(da).cmp(&def_sort_key(db)).then(na.cmp(nb)));

        for (name, defs) in entries {
            let prefix = find_public_prefix(name);
            if prefix.is_none() {
                continue;
            }
            if !EnvironmentVariable::is_secret_name(name) {
                continue;
            }
            let origins: Vec<crate::models::Origin> = defs.iter().map(|d| d.origin.clone()).collect();
            findings.push(make_finding(
                "public-prefix",
                Severity::Error,
                name,
                format!("{} uses public prefix \"{}\"; secret-looking variables with this prefix are exposed to client bundles", name, prefix.unwrap()),
                origins,
            ));
        }

        findings
    }
}