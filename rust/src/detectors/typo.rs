use crate::detectors::{Detector, IndexedModel, def_sort_key, make_finding, origin_sort_key};
use crate::models::{Finding, Origin, Severity};

fn levenshtein(a: &str, b: &str) -> usize {
    let mut matrix: Vec<Vec<usize>> = vec![vec![0; a.len() + 1]; b.len() + 1];
    for (i, item) in matrix.iter_mut().enumerate() {
        item[0] = i;
    }
    for (j, item) in matrix[0].iter_mut().enumerate() {
        *item = j;
    }

    for i in 1..=b.len() {
        for j in 1..=a.len() {
            let cost = if b.as_bytes()[i - 1] == a.as_bytes()[j - 1] { 0 } else { 1 };
            matrix[i][j] = (matrix[i - 1][j] + 1)
                .min(matrix[i][j - 1] + 1)
                .min(matrix[i - 1][j - 1] + cost);
        }
    }
    matrix[b.len()][a.len()]
}

/// Earliest (file, line) a name is referenced at, across usages and
/// compose/action definitions — used to order the referenced-but-undefined
/// names to match the reference CLI's insertion order.
fn reference_sort_key(index: &IndexedModel, name: &str) -> (String, usize) {
    let mut origins: Vec<Origin> = Vec::new();
    if let Some(o) = index.usages.get(name) {
        origins.extend(o.iter().cloned());
    }
    if let Some(d) = index.compose_definitions.get(name) {
        origins.extend(d.iter().map(|d| d.origin.clone()));
    }
    if let Some(d) = index.action_definitions.get(name) {
        origins.extend(d.iter().map(|d| d.origin.clone()));
    }
    origin_sort_key(&origins)
}

fn is_likely_typo(a: &str, b: &str) -> bool {
    if a == b {
        return false;
    }
    if a.len() < 4 || b.len() < 4 {
        return false;
    }
    let distance = levenshtein(a, b);
    let min_len = a.len().min(b.len());
    // Distance of 1 is always flagged for names >= 4 chars.
    // Distance of 2 is flagged for names >= 6 chars.
    // Larger distances only when names are long and ratio is low.
    if distance == 1 {
        return true;
    }
    if distance == 2 {
        return min_len >= 6;
    }
    if distance == 3 {
        return min_len >= 10;
    }
    false
}

/// Typo detector: pairs names that are referenced but not defined with names
/// that are defined but not referenced, and have a small edit distance.
///
/// Example: `DATABSE_URL` referenced in compose but `DATABASE_URL` defined in
/// `.env` produces "did you mean DATABASE_URL?".
pub struct TypoDetector;

impl Detector for TypoDetector {
    fn id(&self) -> &'static str {
        "typo"
    }

    fn name(&self) -> &'static str {
        "typo"
    }

    fn description(&self) -> &'static str {
        "A referenced variable name is very similar to a defined variable name and may be a typo."
    }

    fn detect(&self, index: &IndexedModel) -> Vec<Finding> {
        let mut findings = Vec::new();

        let defined: std::collections::HashSet<&String> = index.env_definitions.keys().collect();
        let mut used: std::collections::HashSet<String> = index.usages.keys().cloned().collect();
        for name in index.compose_definitions.keys() {
            used.insert(name.clone());
        }
        for name in index.action_definitions.keys() {
            used.insert(name.clone());
        }

        // Names referenced but not defined anywhere, ordered by where they are
        // first referenced (usages, then compose/action defs) to match the
        // reference CLI's insertion-ordered `used` set.
        let mut undefined_names: Vec<&String> =
            used.iter().filter(|n| !defined.contains(n)).collect();
        undefined_names.sort_by(|a, b| {
            reference_sort_key(index, a)
                .cmp(&reference_sort_key(index, b))
                .then(a.cmp(b))
        });
        // Names defined but never referenced anywhere, ordered by parse order.
        let mut unused_names: Vec<&String> =
            index.env_definitions.keys().filter(|n| !used.contains(*n)).collect();
        unused_names.sort_by(|a, b| {
            let ka = index.env_definitions.get(*a).map(|d| def_sort_key(d)).unwrap_or_default();
            let kb = index.env_definitions.get(*b).map(|d| def_sort_key(d)).unwrap_or_default();
            ka.cmp(&kb).then(a.cmp(b))
        });

        let mut seen = std::collections::HashSet::new();

        for undefined_name in &undefined_names {
            for unused_name in &unused_names {
                if !is_likely_typo(undefined_name, unused_name) {
                    continue;
                }
                let pair_key = {
                    let mut v = vec![(*undefined_name).clone(), (**unused_name).clone()];
                    v.sort();
                    v.join("\0")
                };
                if seen.insert(pair_key) {
                    let origins = index.usages.get(*undefined_name).cloned().unwrap_or_default();
                    findings.push(make_finding(
                        "typo",
                        Severity::Warning,
                        undefined_name,
                        format!(
                            "did you mean \"{}\"? ({} is referenced but not defined, {} is defined but unused)",
                            unused_name, undefined_name, unused_name
                        ),
                        origins.into_iter().take(3).collect(),
                    ));
                }
            }
        }

        findings
    }
}