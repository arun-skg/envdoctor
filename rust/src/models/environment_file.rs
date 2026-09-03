use camino::Utf8PathBuf;
use serde::{Deserialize, Serialize};
use crate::models::EnvironmentVariable;

/// The format of a parsed file.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum FileFormat {
    Dotenv,
    DockerCompose,
    GithubActions,
    Kubernetes,
    Source,
}

/// The parsed contents of a single file, normalized to envdoctor's model.
///
/// - `variables`: names defined (or referenced with a value) in this file.
/// - `usages`: names read in this file without a value (source `process.env.X`,
///   `${VAR}` interpolation, `${{ secrets.X }}`).
///
/// Both lists are flattened — every name observed in the file appears in
/// exactly one of them.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnvironmentFile {
    /// Path the file was read from.
    pub file_path: Utf8PathBuf,
    pub format: FileFormat,
    /// Environment label for dotenv files ("development", "production", ...).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub environment: Option<String>,
    pub variables: Vec<EnvironmentVariable>,
    pub usages: Vec<EnvironmentVariable>,
}

impl EnvironmentFile {
    /// Names defined in a file, deduplicated, in first-seen order.
    pub fn defined_names(&self) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        self.variables
            .iter()
            .filter_map(|v| {
                if seen.insert(v.name.clone()) {
                    Some(v.name.clone())
                } else {
                    None
                }
            })
            .collect()
    }

    /// Names used in a file, deduplicated, in first-seen order.
    pub fn used_names(&self) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        self.usages
            .iter()
            .filter_map(|v| {
                if seen.insert(v.name.clone()) {
                    Some(v.name.clone())
                } else {
                    None
                }
            })
            .collect()
    }
}