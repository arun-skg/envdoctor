use camino::Utf8Path;
use yaml_rust::YamlLoader;
use crate::models::{EnvironmentFile, EnvironmentVariable, FileFormat, Origin, OriginFormat, OriginKind};
use crate::parsers::{Parser, yaml_interp::line_for_offset};

const SECRET_REF_RE_STR: &str = r"\$\{\{\s*(secrets|vars)\.([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}";

/// Parser for GitHub Actions workflow files (`.github/workflows/*.{yml,yaml}`).
///
/// Definitions come from `env:` blocks at the workflow, job, and step level.
/// `${{ secrets.NAME }}` / `${{ vars.NAME }}` and `$VAR` / `${VAR}`
/// interpolations anywhere in the file become usages.
pub struct GithubActionsParser;

impl Parser for GithubActionsParser {
    fn id(&self) -> &'static str {
        "github-actions"
    }

    fn match_path(&self, file_path: &Utf8Path) -> bool {
        let base = file_path.file_name().unwrap_or("");
        let is_workflow = file_path.as_str().contains("/.github/workflows/");
        is_workflow && (base.ends_with(".yml") || base.ends_with(".yaml"))
    }

    fn parse(&self, content: &str, file_path: &Utf8Path) -> EnvironmentFile {
        let doc = YamlLoader::load_from_str(content).ok().and_then(|docs| docs.into_iter().next());
        let mut variables = Vec::new();

        if let Some(doc) = doc {
            collect_env_blocks(&doc, content, file_path, &mut variables);
        }

        let mut usages = Vec::new();
        let secret_ref_re = regex::Regex::new(SECRET_REF_RE_STR).unwrap();

        // ${{ secrets.X }} / ${{ vars.X }} → usages.
        for mat in secret_ref_re.find_iter(content) {
            if let Some(caps) = secret_ref_re.captures(mat.as_str()) {
                if let Some(name) = caps.get(2).map(|m| m.as_str().to_string()) {
                    let subkind = caps.get(1).map(|m| m.as_str()).unwrap_or("secrets");
                    let origin = Origin {
                        file_path: file_path.to_path_buf(),
                        line: Some(line_for_offset(content, mat.start())),
                        kind: OriginKind::Usage,
                        environment: None,
                        format: Some(OriginFormat::GithubActions),
                        subkind: Some(if subkind == "vars" { "vars".to_string() } else { "secrets".to_string() }),
                    };
                    usages.push(EnvironmentVariable::create(name, None, vec![origin], None));
                }
            }
        }

        // $VAR / ${VAR} → usages.
        for interp in crate::parsers::yaml_interp::scan_interpolations(content) {
            let origin = Origin {
                file_path: file_path.to_path_buf(),
                line: Some(interp.line),
                kind: OriginKind::Usage,
                environment: None,
                format: Some(OriginFormat::GithubActions),
                subkind: None,
            };
            usages.push(EnvironmentVariable::create(interp.name, None, vec![origin], None));
        }

        EnvironmentFile {
            file_path: file_path.to_path_buf(),
            format: FileFormat::GithubActions,
            environment: None,
            variables: EnvironmentVariable::merge(variables),
            usages: EnvironmentVariable::merge(usages),
        }
    }
}

/// Recursively collect every `env:` block as definition variables.
fn collect_env_blocks(
    node: &yaml_rust::Yaml,
    content: &str,
    file_path: &Utf8Path,
    out: &mut Vec<EnvironmentVariable>,
) {
    match node {
        yaml_rust::Yaml::Array(arr) => {
            for item in arr {
                collect_env_blocks(item, content, file_path, out);
            }
        }
        yaml_rust::Yaml::Hash(obj) => {
            if let Some(env) = obj.get(&yaml_rust::Yaml::String("env".to_string())) {
                if let yaml_rust::Yaml::Hash(env_map) = env {
                    for (key_yaml, value_yaml) in env_map {
                        let key = key_yaml.as_str().unwrap_or("").to_string();
                        if key.is_empty() {
                            continue;
                        }
                        let value = if value_yaml.is_badvalue() || value_yaml.is_null() {
                            None
                        } else {
                            Some(value_yaml.as_str().unwrap_or("").to_string())
                        };

                        let origin = Origin {
                            file_path: file_path.to_path_buf(),
                            line: line_for_name(content, &key),
                            kind: if value.is_none() { OriginKind::Reference } else { OriginKind::Definition },
                            environment: None,
                            format: Some(OriginFormat::GithubActions),
                            subkind: None,
                        };
                        out.push(EnvironmentVariable::create(key, value, vec![origin], None));
                    }
                }
            }

            for (_, value) in obj {
                collect_env_blocks(value, content, file_path, out);
            }
        }
        _ => {}
    }
}

/// Best-effort line lookup for an `env:` key in the raw YAML text.
fn line_for_name(content: &str, name: &str) -> Option<usize> {
    let escaped = regex::escape(name);
    let pattern = format!(r#"^\s*["']?{}["']?\s*:"#, escaped);
    let re = regex::Regex::new(&pattern).ok()?;
    re.find(content).map(|m| line_for_offset(content, m.start()))
}