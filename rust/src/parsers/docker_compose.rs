use camino::Utf8Path;
use yaml_rust::YamlLoader;
use crate::models::{EnvironmentFile, EnvironmentVariable, FileFormat, Origin, OriginFormat, OriginKind};
use crate::parsers::{Parser, yaml_interp::{line_for_offset, scan_interpolations}};

const COMPOSE_BASENAMES: &[&str] = &[
    "docker-compose.yml",
    "docker-compose.yaml",
    "docker-compose.override.yml",
    "docker-compose.override.yaml",
    "compose.yml",
    "compose.yaml",
];

/// Parser for docker-compose files.
///
/// Definitions come from `services.<name>.environment:` blocks (both the map
/// and the list form). Bare list entries (`- FOO`) become value-less
/// definitions. `$VAR` / `${VAR}` interpolation anywhere in the file becomes
/// usages.
pub struct DockerComposeParser;

impl Parser for DockerComposeParser {
    fn id(&self) -> &'static str {
        "docker-compose"
    }

    fn match_path(&self, file_path: &Utf8Path) -> bool {
        COMPOSE_BASENAMES.contains(&file_path.file_name().unwrap_or(""))
    }

    fn parse(&self, content: &str, file_path: &Utf8Path) -> EnvironmentFile {
        let doc = YamlLoader::load_from_str(content).ok().and_then(|docs| docs.into_iter().next());
        let mut variables = Vec::new();

        if let Some(doc) = doc {
            if let Some(services) = doc["services"].as_hash() {
                for (_, service_value) in services {
                    let env_vec = if let Some(vec) = service_value["environment"].as_vec() {
                        vec.iter().map(|v| (yaml_rust::Yaml::String("".to_string()), v.clone())).collect::<Vec<_>>()
                    } else if let Some(hash) = service_value["environment"].as_hash() {
                        hash.iter().map(|(k,v)| (k.clone(), v.clone())).collect::<Vec<_>>()
                    } else {
                        continue;
                    };
                    for entry in normalize_environment(env_vec, content, file_path) {
                        variables.push(entry);
                    }
                }
            }
        }

        // `$VAR` / `${VAR}` interpolation → usages.
        let mut usages = Vec::new();
        for interp in scan_interpolations(content) {
            let origin = Origin {
                file_path: file_path.to_path_buf(),
                line: Some(interp.line),
                kind: OriginKind::Usage,
                environment: None,
                format: Some(OriginFormat::DockerCompose),
                subkind: None,
            };
            usages.push(EnvironmentVariable::create(interp.name, None, vec![origin], None));
        }

        EnvironmentFile {
            file_path: file_path.to_path_buf(),
            format: FileFormat::DockerCompose,
            environment: None,
            variables: EnvironmentVariable::merge(variables),
            usages: EnvironmentVariable::merge(usages),
        }
    }
}

/// Flatten a service's `environment:` value into definition variables.
fn normalize_environment(
    env: Vec<(yaml_rust::Yaml, yaml_rust::Yaml)>,
    content: &str,
    file_path: &Utf8Path,
) -> Vec<EnvironmentVariable> {
    let mut variables = Vec::new();

    for (key_yaml, value_yaml) in env {
        let mut key = key_yaml.as_str().unwrap_or("").to_string();

        let value = if key.is_empty() {
            // List form (`- KEY=value` or bare `- KEY`): the whole entry is the
            // string value, so split it into name and optional value ourselves.
            let entry = value_yaml.as_str().unwrap_or("").trim().to_string();
            if entry.is_empty() {
                continue;
            }
            match entry.split_once('=') {
                Some((name, val)) => {
                    key = name.trim().to_string();
                    Some(val.to_string())
                }
                None => {
                    key = entry;
                    None
                }
            }
        } else if value_yaml.is_badvalue() || value_yaml.is_null() {
            None
        } else {
            Some(value_yaml.as_str().unwrap_or("").to_string())
        };

        if key.is_empty() {
            continue;
        }

        let origin = Origin {
            file_path: file_path.to_path_buf(),
            line: line_for_name(content, &key),
            kind: if value.is_none() { OriginKind::Reference } else { OriginKind::Definition },
            environment: None,
            format: Some(OriginFormat::DockerCompose),
            subkind: None,
        };
        variables.push(EnvironmentVariable::create(key, value, vec![origin], None));
    }

    variables
}

/// Best-effort line lookup for a definition name in the raw YAML text.
fn line_for_name(content: &str, name: &str) -> Option<usize> {
    let escaped = regex::escape(name);
    // Supports both map form (`KEY: value`) and list form (`- KEY=value`).
    // `(?m)` makes `^` match at each line start, mirroring the TS `m` flag.
    let pattern = format!(r#"(?m)^\s*[- ]*["']?{}["']?\s*[:=]"#, escaped);
    let re = regex::Regex::new(&pattern).ok()?;
    re.find(content).map(|m| line_for_offset(content, m.start()))
}