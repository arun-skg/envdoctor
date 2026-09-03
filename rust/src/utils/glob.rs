use regex::Regex;
use std::sync::OnceLock;

/// A tiny glob-to-regex converter for matching variable names and file paths
/// against config patterns (`ignore_variables: ["AWS_*"]`, environment
/// overrides, etc.). Supports `*` (within a segment), `**`, and `?`.
pub fn glob_to_regex(pattern: &str) -> Regex {
    static CACHE: OnceLock<std::collections::HashMap<String, Regex>> = OnceLock::new();
    let cache = CACHE.get_or_init(std::collections::HashMap::new);

    if let Some(re) = cache.get(pattern) {
        return re.clone();
    }

    let mut re_str = String::with_capacity(pattern.len() * 2);
    re_str.push('^');

    let mut i = 0;
    let chars: Vec<char> = pattern.chars().collect();
    while i < chars.len() {
        let c = chars[i];
        match c {
            '*' => {
                if i + 1 < chars.len() && chars[i + 1] == '*' {
                    re_str.push_str(".*");
                    i += 2;
                } else {
                    re_str.push_str("[^/]*");
                    i += 1;
                }
            }
            '?' => {
                re_str.push_str("[^/]");
                i += 1;
            }
            _ => {
                // Escape regex special characters
                if ".+?^${}()|[]\\".contains(c) {
                    re_str.push('\\');
                }
                re_str.push(c);
                i += 1;
            }
        }
    }
    re_str.push('$');

    let re = Regex::new(&re_str).expect("Invalid regex from glob pattern");
    // Note: we can't easily cache with OnceLock since we need mutable access
    // For now, just return the regex
    re
}

/// Check if a value matches a glob pattern.
pub fn matches_glob(pattern: &str, value: &str) -> bool {
    glob_to_regex(pattern).is_match(value)
}

/// Check if a value matches any of the glob patterns.
pub fn matches_any_glob(patterns: &[String], value: &str) -> bool {
    patterns.iter().any(|p| matches_glob(p, value))
}