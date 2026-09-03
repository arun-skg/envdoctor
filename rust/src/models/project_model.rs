use camino::Utf8PathBuf;
use serde::{Deserialize, Serialize};
use crate::config::EnvdoctorConfig;
use crate::models::EnvironmentFile;

/// The fully assembled, format-agnostic view of a project, produced by
/// `core/model.rs` from discovered and parsed files. This is the single input
/// to the audit engine — detectors never look at raw file formats.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectModel {
    /// The project root the model was built from.
    pub root_dir: Utf8PathBuf,
    /// The resolved envdoctor config for this project.
    pub config: EnvdoctorConfig,
    /// Parsed `.env*` files, each tagged with an environment label.
    pub env_files: Vec<EnvironmentFile>,
    /// Parsed docker-compose files.
    pub compose_files: Vec<EnvironmentFile>,
    /// Parsed GitHub Actions workflow files.
    pub action_files: Vec<EnvironmentFile>,
    /// Parsed Kubernetes manifest files.
    pub k8s_files: Vec<EnvironmentFile>,
    /// Source code files scanned for `process.env` / `import.meta.env` usage.
    pub source_files: Vec<EnvironmentFile>,
    /// Every file that was scanned, in any format.
    pub all_files: Vec<EnvironmentFile>,
    /// Files that matched a parser but failed to parse (kept for reporting).
    pub parse_errors: Vec<ParseError>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParseError {
    pub file_path: Utf8PathBuf,
    pub error: String,
}

impl ProjectModel {
    /// All definitions (variables with values) across the whole project.
    pub fn all_definitions(&self) -> Vec<&crate::models::EnvironmentVariable> {
        self.env_files
            .iter()
            .flat_map(|f| &f.variables)
            .chain(self.compose_files.iter().flat_map(|f| &f.variables))
            .chain(self.action_files.iter().flat_map(|f| &f.variables))
            .collect()
    }

    /// All usages (name references without values) across the whole project.
    pub fn all_usages(&self) -> Vec<&crate::models::EnvironmentVariable> {
        self.env_files
            .iter()
            .flat_map(|f| &f.usages)
            .chain(self.compose_files.iter().flat_map(|f| &f.usages))
            .chain(self.action_files.iter().flat_map(|f| &f.usages))
            .chain(self.source_files.iter().flat_map(|f| &f.usages))
            .collect()
    }

    /// Flatten every origin for a name into a deduplicated list.
    pub fn origins_for_name(&self, name: &str) -> Vec<crate::models::Origin> {
        use std::collections::HashMap;
        let mut seen = HashMap::new();

        for file in &self.all_files {
            for v in &file.variables {
                if v.name == name {
                    for origin in &v.origins {
                        let key = format!("{}:{:?}:{:?}", origin.file_path, origin.line, origin.kind);
                        if !seen.contains_key(&key) {
                            seen.insert(key, origin.clone());
                        }
                    }
                }
            }
            for v in &file.usages {
                if v.name == name {
                    for origin in &v.origins {
                        let key = format!("{}:{:?}:{:?}", origin.file_path, origin.line, origin.kind);
                        if !seen.contains_key(&key) {
                            seen.insert(key, origin.clone());
                        }
                    }
                }
            }
        }

        seen.into_values().collect()
    }
}