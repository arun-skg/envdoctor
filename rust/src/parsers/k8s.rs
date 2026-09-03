use camino::Utf8Path;
use yaml_rust::YamlLoader;
use crate::models::{EnvironmentFile, EnvironmentVariable, FileFormat, Origin, OriginFormat, OriginKind};
use crate::parsers::{Parser, yaml_interp::scan_interpolations};

fn is_yaml(file_path: &Utf8Path) -> bool {
    let ext = file_path.extension().unwrap_or("");
    ext == "yaml" || ext == "yml"
}

fn looks_like_k8s(doc: &yaml_rust::Yaml) -> bool {
    if let Some(obj) = doc.as_hash() {
        obj.get(&yaml_rust::Yaml::String("apiVersion".to_string())).is_some()
            && obj.get(&yaml_rust::Yaml::String("kind".to_string())).is_some()
    } else {
        false
    }
}

/// Parser for Kubernetes manifests.
///
/// Matches YAML files that look like Kubernetes resources (have apiVersion and
/// kind). Extracts container environment definitions and `${VAR}` / `$VAR`
/// interpolations from command/args/env values.
pub struct K8sParser;

impl Parser for K8sParser {
    fn id(&self) -> &'static str {
        "kubernetes"
    }

    fn match_path(&self, file_path: &Utf8Path) -> bool {
        is_yaml(file_path)
    }

    fn parse(&self, content: &str, file_path: &Utf8Path) -> EnvironmentFile {
        let doc_array = YamlLoader::load_from_str(content)
            .ok()
            .map(|docs| {
                if docs.is_empty() {
                    vec![yaml_rust::Yaml::Null]
                } else {
                    docs
                }
            })
            .unwrap_or_else(|| vec![yaml_rust::Yaml::Null]);

        let mut variables = Vec::new();
        let mut usages = Vec::new();

        for doc in &doc_array {
            if looks_like_k8s(doc) {
                walk_resource(doc, content, file_path, &mut variables, &mut usages);
            }
        }

        EnvironmentFile {
            file_path: file_path.to_path_buf(),
            format: FileFormat::Kubernetes,
            environment: None,
            variables: EnvironmentVariable::merge(variables),
            usages: EnvironmentVariable::merge(usages),
        }
    }
}

fn origin_at(
    file_path: &Utf8Path,
    line: Option<usize>,
    kind: OriginKind,
) -> Origin {
    Origin {
        file_path: file_path.to_path_buf(),
        line,
        kind,
        environment: None,
        format: Some(OriginFormat::Kubernetes),
        subkind: None,
    }
}

fn walk_resource(
    doc: &yaml_rust::Yaml,
    _content: &str,
    file_path: &Utf8Path,
    variables: &mut Vec<EnvironmentVariable>,
    usages: &mut Vec<EnvironmentVariable>,
) {
    let kind = doc["kind"].as_str().unwrap_or("");

    // ConfigMap data keys become definitions.
    if kind == "ConfigMap" {
        if let Some(data) = doc["data"].as_hash() {
            for (key, value) in data {
                let key_str = key.as_str().unwrap_or("").to_string();
                let value_str = value.as_str().unwrap_or("").to_string();
                if !key_str.is_empty() {
                    variables.push(EnvironmentVariable::create(
                        key_str,
                        Some(value_str),
                        vec![origin_at(file_path, None, OriginKind::Definition)],
                        None,
                    ));
                }
            }
        }
        return;
    }

    let spec = get_object(doc, "spec");
    let pod_spec = spec
        .and_then(|s| get_object(s, "template"))
        .and_then(|t| get_object(t, "spec"))
        .unwrap_or(spec.unwrap_or(doc));

    let containers = get_array(pod_spec, "containers")
        .into_iter()
        .chain(get_array(pod_spec, "initContainers").into_iter())
        .flatten()
        .collect::<Vec<_>>();

    for container in containers {
        let env = get_array(container, "env").unwrap_or_default();
        for raw in env {
            if let Some(entry) = raw.as_hash() {
                let name = entry.get(&yaml_rust::Yaml::String("name".to_string()))
                    .and_then(|n| n.as_str())
                    .unwrap_or("")
                    .to_string();
                if name.is_empty() {
                    continue;
                }

                if let Some(value) = entry.get(&yaml_rust::Yaml::String("value".to_string())) {
                    let value_str = value.as_str().unwrap_or("").to_string();
                    variables.push(EnvironmentVariable::create(
                        name,
                        Some(value_str),
                        vec![origin_at(file_path, None, OriginKind::Definition)],
                        None,
                    ));
                } else if entry.get(&yaml_rust::Yaml::String("valueFrom".to_string())).is_some() {
                    // Referenced but value provided elsewhere (ConfigMap/Secret).
                    usages.push(EnvironmentVariable::create(
                        name,
                        None,
                        vec![origin_at(file_path, None, OriginKind::Usage)],
                        None,
                    ));
                }
            }
        }

        // Interpolations in command/args.
        for key in &["command", "args"] {
            if let Some(list) = get_array(container, key) {
                for item in list {
                    if let Some(item_str) = item.as_str() {
                        for interp in scan_interpolations(item_str) {
                            usages.push(EnvironmentVariable::create(
                                interp.name,
                                None,
                                vec![origin_at(file_path, Some(interp.line), OriginKind::Usage)],
                                None,
                            ));
                        }
                    }
                }
            }
        }
    }
}

fn get_object<'a>(obj: &'a yaml_rust::Yaml, key: &str) -> Option<&'a yaml_rust::Yaml> {
    if let Some(map) = obj.as_hash() {
        map.get(&yaml_rust::Yaml::String(key.to_string()))
    } else {
        None
    }
}

fn get_array<'a>(obj: &'a yaml_rust::Yaml, key: &str) -> Option<Vec<&'a yaml_rust::Yaml>> {
    get_object(obj, key).and_then(|v| v.as_vec()).map(|v| v.iter().collect())
}