use crate::models::{ProjectModel, RuntimeSnapshot, EnvironmentVariable, Origin, OriginKind, OriginFormat};
use crate::models::runtime_snapshot::{OsInfo, ToolInfo};
use crate::config::EnvdoctorConfig;
use camino::Utf8PathBuf;
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

/// Collect a runtime snapshot of environment variables.
pub fn collect_runtime(
    model: &ProjectModel,
    _config: &EnvdoctorConfig,
) -> Result<RuntimeSnapshot, anyhow::Error> {
    let mut env_vars = HashMap::new();
    let mut origins: Vec<Origin> = Vec::new();

    // Collect from process environment
    for (name, value) in std::env::vars() {
        let var_type = crate::utils::type_infer::infer_type(Some(&value));
        let is_secret = EnvironmentVariable::is_secret_name(&name);

        let origin = Origin {
            file_path: Utf8PathBuf::from("<process>"),
            line: None,
            kind: OriginKind::Definition,
            environment: Some("runtime".to_string()),
            format: Some(OriginFormat::Source),
            subkind: Some("process".to_string()),
        };

        let ev = EnvironmentVariable {
            name: name.clone(),
            value: Some(value.clone()),
            is_secret,
            var_type,
            origins: vec![origin.clone()],
            ignore_rules: None,
        };

        env_vars.insert(name, ev);
        origins.push(origin);
    }

    // Also include vars from the model that aren't in process env
    for file in &model.env_files {
        for v in &file.variables {
            if !env_vars.contains_key(&v.name) {
                env_vars.insert(v.name.clone(), v.clone());
            }
        }
    }

    let mut variables: Vec<EnvironmentVariable> = env_vars.into_values().collect();
    variables.sort_by(|a, b| a.name.cmp(&b.name));

    let captured_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)?
        .as_secs()
        .to_string();

    // Get OS info
    let os = OsInfo {
        platform: std::env::consts::OS.to_string(),
        arch: std::env::consts::ARCH.to_string(),
        release: "unknown".to_string(),
    };

    // Get PATH entries
    let path = std::env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .map(|s| s.to_string())
        .collect();

    // Get globals (npm, pip, cargo, etc.)
    let globals = HashMap::new();

    // Get env flag names (variables that look like feature flags)
    let env_flag_names: Vec<String> = variables
        .iter()
        .filter(|v| v.name.starts_with("FEATURE_") || v.name.starts_with("ENABLE_") || v.name.starts_with("FLAG_"))
        .map(|v| v.name.clone())
        .collect();

    // Get tools (node, npm, cargo, etc.)
    let mut tools = Vec::new();
    if let Ok(output) = std::process::Command::new("node").arg("--version").output() {
        if output.status.success() {
            tools.push(ToolInfo {
                tool: "node".to_string(),
                version: String::from_utf8_lossy(&output.stdout).trim().to_string(),
                resolved_from: "PATH".to_string(),
            });
        }
    }
    if let Ok(output) = std::process::Command::new("npm").arg("--version").output() {
        if output.status.success() {
            tools.push(ToolInfo {
                tool: "npm".to_string(),
                version: String::from_utf8_lossy(&output.stdout).trim().to_string(),
                resolved_from: "PATH".to_string(),
            });
        }
    }
    if let Ok(output) = std::process::Command::new("cargo").arg("--version").output() {
        if output.status.success() {
            tools.push(ToolInfo {
                tool: "cargo".to_string(),
                version: String::from_utf8_lossy(&output.stdout).trim().to_string(),
                resolved_from: "PATH".to_string(),
            });
        }
    }

    Ok(RuntimeSnapshot {
        schema: crate::models::runtime_snapshot::SNAPSHOT_SCHEMA.to_string(),
        captured_at,
        os,
        tools,
        path,
        globals,
        env_flag_names,
    })
}