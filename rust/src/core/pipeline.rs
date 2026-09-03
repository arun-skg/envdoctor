use crate::config::{load_config, EnvdoctorConfig};
use crate::core::audit::run_audit;
use crate::core::discover::{discover_files, discover_source_files};
use crate::core::model::assemble_model;
use crate::detectors::index::build_index;
use crate::models::ProjectModel;
use camino::Utf8PathBuf;

/// Load a project: discover files, assemble the model, and return it together
/// with the config used. This is the main entry for non-API commands.
pub async fn load_project(root_dir: &Utf8PathBuf) -> (ProjectModel, EnvdoctorConfig) {
    load_project_filtered(root_dir, None).await
}

/// Like [`load_project`], but restricts the assembled model to `changed` files
/// when a set is provided (used by `scan --staged` / `--since`). Files outside
/// the set are dropped before parsing.
pub async fn load_project_filtered(
    root_dir: &Utf8PathBuf,
    changed: Option<&std::collections::HashSet<Utf8PathBuf>>,
) -> (ProjectModel, EnvdoctorConfig) {
    let config = load_config(root_dir).await.unwrap_or_default();

    let env_files = discover_files(root_dir, &config);
    let source_files = discover_source_files(root_dir, &config);

    // Combine env + source files for model assembly
    let mut all_paths = env_files;
    all_paths.extend(source_files);

    if let Some(changed) = changed {
        all_paths.retain(|p| changed.contains(p));
    }

    let model = assemble_model(root_dir, &config, &all_paths);
    (model, config)
}

/// Run a complete audit: load project, build index, run detectors, return
/// the aggregated findings.
pub async fn audit_project(root_dir: &Utf8PathBuf) -> Vec<crate::models::Finding> {
    let (model, config) = load_project(root_dir).await;
    let index = build_index(&model);
    run_audit(&model, &config, &index)
}

/// Build a summary from a list of findings and the scanned project model.
pub fn summarize(
    model: &ProjectModel,
    findings: &[crate::models::Finding],
) -> crate::models::AuditSummary {
    let mut errors = 0;
    let mut warnings = 0;
    let mut infos = 0;
    for f in findings {
        match f.severity {
            crate::models::Severity::Error => errors += 1,
            crate::models::Severity::Warning => warnings += 1,
            crate::models::Severity::Info => infos += 1,
        }
    }
    let total = errors + warnings + infos;
    crate::models::AuditSummary {
        files_scanned: model.all_files.len(),
        variables_found: distinct_variable_count(model),
        errors,
        warnings,
        infos,
        total,
    }
}

/// Count distinct variable names across every scanned file (definitions and
/// usages), matching the reference implementation's summary metric.
fn distinct_variable_count(model: &ProjectModel) -> usize {
    use std::collections::HashSet;
    let mut names = HashSet::new();
    for file in &model.all_files {
        for v in &file.variables {
            names.insert(v.name.clone());
        }
        for v in &file.usages {
            names.insert(v.name.clone());
        }
    }
    names.len()
}
