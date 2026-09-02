use crate::models::{Origin, ProjectModel};
use crate::detectors::{Definition, IndexedModel};
use std::collections::{HashMap, HashSet};

/// Build the format-agnostic index detectors operate on.
pub fn build_index(model: &ProjectModel) -> IndexedModel {
    let mut env_definitions: HashMap<String, Vec<Definition>> = HashMap::new();
    let mut compose_definitions: HashMap<String, Vec<Definition>> = HashMap::new();
    let mut action_definitions: HashMap<String, Vec<Definition>> = HashMap::new();
    let mut k8s_definitions: HashMap<String, Vec<Definition>> = HashMap::new();
    let mut usages: HashMap<String, Vec<Origin>> = HashMap::new();
    let mut source_usages: HashMap<String, Vec<Origin>> = HashMap::new();
    let mut example_names: HashSet<String> = HashSet::new();
    let mut env_labels_set: HashSet<String> = HashSet::new();

    // Helper to push a definition into a map
    let push_def = |map: &mut HashMap<String, Vec<Definition>>, def: Definition| {
        map.entry(def.name.clone()).or_default().push(def);
    };

    // Helper to push an origin into a map
    let push_origin = |map: &mut HashMap<String, Vec<Origin>>, name: &str, origin: Origin| {
        map.entry(name.to_string()).or_default().push(origin);
    };

    // Process env files
    for file in &model.env_files {
        if file.environment.as_deref() == Some("example") {
            // .env.example documents what *should* exist but is not a runtime
            // value. Add to example_names only — do NOT add to env_definitions
            // (and skip usages), matching the TS reference.
            for v in &file.variables {
                example_names.insert(v.name.clone());
            }
            continue;
        }

        if let Some(env_label) = &file.environment {
            env_labels_set.insert(env_label.clone());
        }

        for v in &file.variables {
            let def = Definition {
                name: v.name.clone(),
                value: v.value.clone(),
                var_type: v.var_type,
                is_secret: v.is_secret,
                environment: file.environment.clone(),
                origin: v.origins.first().cloned().unwrap_or_else(|| Origin {
                    file_path: file.file_path.clone(),
                    line: None,
                    kind: crate::models::OriginKind::Definition,
                    environment: file.environment.clone(),
                    format: Some(crate::models::OriginFormat::Dotenv),
                    subkind: None,
                }),
            };
            push_def(&mut env_definitions, def);
        }

        for v in &file.usages {
            for origin in &v.origins {
                push_origin(&mut usages, &v.name, origin.clone());
            }
        }
    }

    // Process compose files
    for file in &model.compose_files {
        for v in &file.variables {
            let def = Definition {
                name: v.name.clone(),
                value: v.value.clone(),
                var_type: v.var_type,
                is_secret: v.is_secret,
                environment: None,
                origin: v.origins.first().cloned().unwrap_or_else(|| Origin {
                    file_path: file.file_path.clone(),
                    line: None,
                    kind: crate::models::OriginKind::Definition,
                    environment: None,
                    format: Some(crate::models::OriginFormat::DockerCompose),
                    subkind: None,
                }),
            };
            push_def(&mut compose_definitions, def);
        }

        for v in &file.usages {
            for origin in &v.origins {
                push_origin(&mut usages, &v.name, origin.clone());
            }
        }
    }

    // Process GitHub Actions files
    for file in &model.action_files {
        for v in &file.variables {
            let def = Definition {
                name: v.name.clone(),
                value: v.value.clone(),
                var_type: v.var_type,
                is_secret: v.is_secret,
                environment: None,
                origin: v.origins.first().cloned().unwrap_or_else(|| Origin {
                    file_path: file.file_path.clone(),
                    line: None,
                    kind: crate::models::OriginKind::Definition,
                    environment: None,
                    format: Some(crate::models::OriginFormat::GithubActions),
                    subkind: None,
                }),
            };
            push_def(&mut action_definitions, def);
        }

        for v in &file.usages {
            for origin in &v.origins {
                push_origin(&mut usages, &v.name, origin.clone());
            }
        }
    }

    // Process k8s files
    for file in &model.k8s_files {
        for v in &file.variables {
            let def = Definition {
                name: v.name.clone(),
                value: v.value.clone(),
                var_type: v.var_type,
                is_secret: v.is_secret,
                environment: None,
                origin: v.origins.first().cloned().unwrap_or_else(|| Origin {
                    file_path: file.file_path.clone(),
                    line: None,
                    kind: crate::models::OriginKind::Definition,
                    environment: None,
                    format: Some(crate::models::OriginFormat::Kubernetes),
                    subkind: None,
                }),
            };
            push_def(&mut k8s_definitions, def);
        }

        for v in &file.usages {
            for origin in &v.origins {
                push_origin(&mut usages, &v.name, origin.clone());
            }
        }
    }

    // Process source files
    for file in &model.source_files {
        for v in &file.usages {
            for origin in &v.origins {
                push_origin(&mut usages, &v.name, origin.clone());
                push_origin(&mut source_usages, &v.name, origin.clone());
            }
        }
    }

    let env_labels: Vec<String> = env_labels_set.into_iter().collect();

    IndexedModel {
        model: model.clone(),
        env_definitions,
        compose_definitions,
        action_definitions,
        k8s_definitions,
        usages,
        source_usages,
        example_names,
        env_labels,
    }
}