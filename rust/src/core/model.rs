use crate::config::EnvdoctorConfig;
use crate::models::{EnvironmentFile, EnvironmentVariable, Origin, ProjectModel};
use crate::parsers::registry::default_registry;
use crate::utils::glob::{matches_any_glob, matches_glob};
use camino::Utf8PathBuf;
use std::collections::HashMap;

/// Assemble a `ProjectModel` from discovered file paths.
///
/// Each file is parsed via the parser registry. Files matching a known
/// extension/format produce an `EnvironmentFile`; files that match a parser
/// but fail to parse produce a `ParseError`.
pub fn assemble_model(
    root_dir: &Utf8PathBuf,
    config: &EnvdoctorConfig,
    discovered: &[Utf8PathBuf],
) -> ProjectModel {
    let registry = default_registry(crate::parsers::RegistryOptions {
        source_extensions: config.source_extensions.clone(),
    });
    let mut env_files = Vec::new();
    let mut compose_files = Vec::new();
    let mut action_files = Vec::new();
    let mut k8s_files = Vec::new();
    let mut source_files = Vec::new();
    let mut all_files = Vec::new();
    let mut parse_errors = Vec::new();

    for path in discovered {
        // Read file content
        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(e) => {
                parse_errors.push(crate::models::ParseError {
                    file_path: path.clone(),
                    error: format!("Cannot read file: {}", e),
                });
                continue;
            }
        };

        // Skip if ignored by config
        if !config.ignore_files.is_empty() {
            if let Ok(rel) = path.strip_prefix(root_dir) {
                let rel_str = rel.as_str();
                if matches_any_glob(&config.ignore_files, rel_str) {
                    continue;
                }
            }
        }

        // Find a parser that handles this file
        let mut parsed: Option<EnvironmentFile> = None;
        for parser in &registry {
            if parser.match_path(path) {
                let file = parser.parse(&content, path);
                parsed = Some(file);
                break;
            }
        }

        if let Some(file) = parsed {
            match file.format {
                crate::models::FileFormat::Dotenv => env_files.push(file.clone()),
                crate::models::FileFormat::DockerCompose => compose_files.push(file.clone()),
                crate::models::FileFormat::GithubActions => action_files.push(file.clone()),
                crate::models::FileFormat::Kubernetes => k8s_files.push(file.clone()),
                crate::models::FileFormat::Source => source_files.push(file.clone()),
            }
            all_files.push(file);
        }
    }

    // Apply ignore_variables to parsed variables
    let env_files = apply_ignore_variables(env_files, config);
    let compose_files = apply_ignore_variables(compose_files, config);
    let action_files = apply_ignore_variables(action_files, config);
    let k8s_files = apply_ignore_variables(k8s_files, config);
    let source_files = apply_ignore_variables(source_files, config);

    // Apply environment overrides if configured
    let env_files = apply_environment_overrides(env_files, config);

    ProjectModel {
        root_dir: root_dir.clone(),
        config: config.clone(),
        env_files,
        compose_files,
        action_files,
        k8s_files,
        source_files,
        all_files,
        parse_errors,
    }
}

/// Remove variables whose names match `ignore_variables` globs.
fn apply_ignore_variables(
    files: Vec<EnvironmentFile>,
    config: &EnvdoctorConfig,
) -> Vec<EnvironmentFile> {
    if config.ignore_variables.is_empty() {
        return files;
    }
    files
        .into_iter()
        .map(|mut f| {
            f.variables.retain(|v| !matches_any_glob(&config.ignore_variables, &v.name));
            f.usages.retain(|v| !matches_any_glob(&config.ignore_variables, &v.name));
            f
        })
        .collect()
}

/// If `environments` is configured, override the environment label for files
/// matching the given globs.
fn apply_environment_overrides(
    files: Vec<EnvironmentFile>,
    config: &EnvdoctorConfig,
) -> Vec<EnvironmentFile> {
    let Some(environments) = &config.environments else {
        return files;
    };

    files
        .into_iter()
        .map(|mut f| {
            let rel = f.file_path.clone();
            for (env_label, globs) in environments {
                if matches_any_glob(globs, rel.as_str()) {
                    f.environment = Some(env_label.clone());
                    break;
                }
            }
            f
        })
        .collect()
}

/// Helper to get the environment label from a dotenv file name.
/// Mirrors TS `environment_label_for_dotenv`.
#[allow(dead_code)]
pub fn environment_label_for_dotenv(path: &camino::Utf8Path) -> String {
    crate::parsers::env::environment_label_for_dotenv(path)
}

/// Build the variable name → final type map from schema + inference.
#[allow(dead_code)]
pub fn resolve_schema_types(
    config: &EnvdoctorConfig,
) -> HashMap<String, crate::models::VariableType> {
    let mut map = HashMap::new();
    for (name, schema) in &config.schema {
        if let Some(ref t) = schema.var_type {
            map.insert(name.clone(), t.to_variable_type());
        }
    }
    map
}

/// Determine if a name matches any ignore pattern.
#[allow(dead_code)]
pub fn is_name_ignored(name: &str, patterns: &[String]) -> bool {
    patterns.iter().any(|p| matches_glob(p, name))
}

/// Get all origins for a variable name across a model.
#[allow(dead_code)]
pub fn all_origins_for(model: &ProjectModel, name: &str) -> Vec<Origin> {
    model.origins_for_name(name)
}

/// Get all variables defined in env files.
#[allow(dead_code)]
pub fn all_env_variables(files: &[EnvironmentFile]) -> Vec<&EnvironmentVariable> {
    files.iter().flat_map(|f| &f.variables).collect()
}
