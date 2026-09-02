
/// Helpers for scanning shell-style variable interpolation in YAML-based
/// formats (docker-compose, GitHub Actions). Shared because both formats use
/// `$VAR` / `${VAR}` and need 1-based line numbers for origins.

/// Compute the 1-based line number of a character offset in `content`.
pub fn line_for_offset(content: &str, offset: usize) -> usize {
    let end = offset.min(content.len());
    content[..end].chars().filter(|&c| c == '\n').count() + 1
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Interpolation {
    pub name: String,
    pub line: usize,
}

/// Scan `content` for `$VAR` and `${VAR}` interpolations, honoring the
/// `$$` escape (compose uses `$$` to produce a literal `$`). Returns each
/// interpolation with its line number. `{...}` modifiers (e.g. `${VAR:-x}`,
/// `${VAR-default}`, `${VAR:?msg}`) are stripped — only the name is kept.
pub fn scan_interpolations(content: &str) -> Vec<Interpolation> {
    // Protect escaped `$$` (same length, so offsets stay valid) so the second
    // `$` is never mistaken for a real interpolation.
    let protected_content = content.replace("$$", "");
    let re = regex::Regex::new(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)(?:\s*[:-?+][^}]*)?\}|([A-Za-z_][A-Za-z0-9_]*))").unwrap();
    let mut results = Vec::new();

    for mat in re.find_iter(&protected_content) {
        if let Some(caps) = re.captures(mat.as_str()) {
            let name = caps.get(1).or(caps.get(2)).map(|m| m.as_str().to_string());
            if let Some(name) = name {
                results.push(Interpolation {
                    name,
                    line: line_for_offset(content, mat.start()),
                });
            }
        }
    }

    results
}