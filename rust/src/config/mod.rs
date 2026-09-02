use camino::Utf8PathBuf;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// envdoctor is configured through `envdoctor.config.toml|json` or a
/// `envdoctor` key in package.json. The config is optional — defaults are
/// sensible for most projects. Everything is validated with serde so a bad
/// config fails fast with a clear message instead of behaving mysteriously.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct EnvdoctorConfig {
    /// Glob patterns (relative to the project root) for dotenv files.
    pub env_file_patterns: Vec<String>,
    /// Glob patterns for docker-compose files.
    pub compose_file_patterns: Vec<String>,
    /// Glob patterns for GitHub Actions workflows.
    pub actions_file_patterns: Vec<String>,
    /// Glob patterns for Kubernetes manifests.
    pub k8s_file_patterns: Vec<String>,
    /// File extensions scanned for source usage.
    pub source_extensions: Vec<String>,
    /// Glob patterns of variable names to never report (e.g. "AWS_*").
    pub ignore_variables: Vec<String>,
    /// Glob patterns of files to skip.
    pub ignore_files: Vec<String>,
    /**
     * Explicit environment label → file mapping. When provided it overrides the
     * default label derivation for dotenv files.
     */
    #[serde(skip_serializing_if = "Option::is_none")]
    pub environments: Option<HashMap<String, Vec<String>>>,
    /// Fail the audit when only warnings are present.
    pub strict: bool,
    /**
     * Override severity per detector. Use "off" to disable a detector entirely.
     * Example: `{ unused: "off", "environment-diff": "warn" }`
     */
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    pub rules: HashMap<String, RuleSeverity>,
    /**
     * Per-variable validation schema. Values in env files are checked against
     * these rules.
     */
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    pub schema: HashMap<String, VariableSchema>,
}

impl Default for EnvdoctorConfig {
    fn default() -> Self {
        Self {
            env_file_patterns: vec![".env".into(), ".env.*".into()],
            compose_file_patterns: vec![
                "**/docker-compose*.y*ml".into(),
                "**/compose*.y*ml".into(),
            ],
            actions_file_patterns: vec![".github/workflows/**/*.y*ml".into()],
            k8s_file_patterns: vec![
                "**/*.{deployment,service,statefulset,daemonset,cronjob,job,configmap,secret,ingress,pvc}.y*ml".into(),
                "**/k8s/**/*.y*ml".into(),
                "**/kubernetes/**/*.y*ml".into(),
                "**/manifests/**/*.y*ml".into(),
                "**/deploy/**/*.y*ml".into(),
            ],
            source_extensions: vec!["ts".into(), "tsx".into(), "js".into(), "jsx".into(), "mjs".into(), "cjs".into()],
            ignore_variables: vec![],
            ignore_files: vec![],
            environments: None,
            strict: false,
            rules: HashMap::new(),
            schema: HashMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RuleSeverity {
    Error,
    Warning,
    Off,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct VariableSchema {
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub var_type: Option<SchemaType>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub optional: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enum_values: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub regex: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub min: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max: Option<i64>,
}

impl Default for VariableSchema {
    fn default() -> Self {
        Self {
            var_type: None,
            optional: None,
            enum_values: None,
            regex: None,
            min: None,
            max: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SchemaType {
    String,
    Integer,
    Float,
    Boolean,
    Url,
    Json,
    Enum,
    Regex,
}

impl SchemaType {
    pub fn to_variable_type(&self) -> crate::models::VariableType {
        match self {
            SchemaType::String => crate::models::VariableType::String,
            SchemaType::Integer => crate::models::VariableType::Integer,
            SchemaType::Float => crate::models::VariableType::Float,
            SchemaType::Boolean => crate::models::VariableType::Boolean,
            SchemaType::Url => crate::models::VariableType::Url,
            SchemaType::Json => crate::models::VariableType::Json,
            SchemaType::Enum => crate::models::VariableType::String,
            SchemaType::Regex => crate::models::VariableType::String,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("Could not load config {path}: {reason}. Use envdoctor.config.toml (or package.json#envdoctor).")]
    LoadError { path: String, reason: String },
    #[error("Invalid envdoctor config: {issues}")]
    InvalidConfig { issues: String },
}

/// Load and validate the config for a project root. Falls back to defaults
/// when no config exists. Throws `ConfigError` when a config file is present
/// but invalid (syntax error, wrong shape, or unimportable).
pub async fn load_config(root_dir: &Utf8PathBuf) -> Result<EnvdoctorConfig, ConfigError> {
    // Try to find config file
    let config_path = find_config_file(root_dir).await;
    let pkg_config = read_package_json_config(root_dir).await;

    if config_path.is_none() && pkg_config.is_none() {
        return Ok(EnvdoctorConfig::default());
    }

    let raw: serde_json::Value = if let Some(path) = config_path {
        let content = tokio::fs::read_to_string(&path)
            .await
            .map_err(|e| ConfigError::LoadError {
                path: path.to_string(),
                reason: e.to_string(),
            })?;

        // Try TOML first, then JSON
        if path.extension() == Some("toml") {
            toml::from_str(&content).map_err(|e| ConfigError::InvalidConfig {
                issues: e.to_string(),
            })?
        } else {
            serde_json::from_str(&content).map_err(|e| ConfigError::InvalidConfig {
                issues: e.to_string(),
            })?
        }
    } else {
        pkg_config.unwrap()
    };

    let config: EnvdoctorConfig = serde_json::from_value(raw).map_err(|e| ConfigError::InvalidConfig {
        issues: e.to_string(),
    })?;

    Ok(config)
}

const CONFIG_BASENAMES: &[&str] = &[
    "envdoctor.config.toml",
    "envdoctor.config.json",
];

async fn find_config_file(root_dir: &Utf8PathBuf) -> Option<Utf8PathBuf> {
    for basename in CONFIG_BASENAMES {
        let candidate = root_dir.join(basename);
        if tokio::fs::metadata(&candidate).await.is_ok() {
            return Some(candidate);
        }
    }
    None
}

async fn read_package_json_config(root_dir: &Utf8PathBuf) -> Option<serde_json::Value> {
    let pkg_path = root_dir.join("package.json");
    let content = tokio::fs::read_to_string(&pkg_path).await.ok()?;
    let pkg: serde_json::Value = serde_json::from_str(&content).ok()?;
    pkg.get("envdoctor").cloned()
}

/// Blocking version of `load_config` for CLI commands that don't need async.
pub fn blocking_load_config(root_dir: &Utf8PathBuf) -> Result<EnvdoctorConfig, ConfigError> {
    // Try to find config file
    let config_path = find_config_file_blocking(root_dir);
    let pkg_config = read_package_json_config_blocking(root_dir);

    if config_path.is_none() && pkg_config.is_none() {
        return Ok(EnvdoctorConfig::default());
    }

    let raw: serde_json::Value = if let Some(path) = config_path {
        let content = std::fs::read_to_string(&path)
            .map_err(|e| ConfigError::LoadError {
                path: path.to_string(),
                reason: e.to_string(),
            })?;

        // Try TOML first, then JSON
        if path.extension() == Some("toml") {
            toml::from_str(&content).map_err(|e| ConfigError::InvalidConfig {
                issues: e.to_string(),
            })?
        } else {
            serde_json::from_str(&content).map_err(|e| ConfigError::InvalidConfig {
                issues: e.to_string(),
            })?
        }
    } else {
        pkg_config.unwrap()
    };

    let config: EnvdoctorConfig = serde_json::from_value(raw).map_err(|e| ConfigError::InvalidConfig {
        issues: e.to_string(),
    })?;

    Ok(config)
}

fn find_config_file_blocking(root_dir: &Utf8PathBuf) -> Option<Utf8PathBuf> {
    for basename in CONFIG_BASENAMES {
        let candidate = root_dir.join(basename);
        if std::fs::metadata(&candidate).is_ok() {
            return Some(candidate);
        }
    }
    None
}

fn read_package_json_config_blocking(root_dir: &Utf8PathBuf) -> Option<serde_json::Value> {
    let pkg_path = root_dir.join("package.json");
    let content = std::fs::read_to_string(&pkg_path).ok()?;
    let pkg: serde_json::Value = serde_json::from_str(&content).ok()?;
    pkg.get("envdoctor").cloned()
}