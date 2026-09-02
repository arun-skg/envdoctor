use camino::Utf8PathBuf;
use serde::{Deserialize, Serialize};

/// Where a variable name was seen, and in what role.
///
/// - `Definition`: the variable has a value here (e.g. `FOO=bar` in a .env file,
///   a `environment:` key in compose, an `env:` key in a workflow).
/// - `Reference`: the variable is expected to exist but no value is given here
///   (e.g. a bare `- FOO` compose entry, a workflow `env:` whose value is an
///   expression, or a name listed in `.env.example`).
/// - `Usage`: the variable is read somewhere (source code, `${VAR}` interpolation,
///   `${{ secrets.X }}`).
///
/// Origins carry file paths and line numbers so findings can point at real
/// locations. Values are intentionally NOT carried here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OriginKind {
    Definition,
    Reference,
    Usage,
}

impl OriginKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            OriginKind::Definition => "definition",
            OriginKind::Reference => "reference",
            OriginKind::Usage => "usage",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Origin {
    /// Path to the file where the variable appeared (repo-relative when possible).
    pub file_path: Utf8PathBuf,
    /// 1-based line number when known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub line: Option<usize>,
    pub kind: OriginKind,
    /// Environment label (dotenv files only, e.g. "development", "production").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub environment: Option<String>,
    /// The format the origin came from.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format: Option<OriginFormat>,
    /// Format-specific detail (e.g. "secrets" vs "vars" for GitHub Actions).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subkind: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum OriginFormat {
    Dotenv,
    DockerCompose,
    GithubActions,
    Kubernetes,
    Source,
}

impl Origin {
    pub fn new_definition(file_path: Utf8PathBuf, line: Option<usize>, environment: Option<String>) -> Self {
        Self {
            file_path,
            line,
            kind: OriginKind::Definition,
            environment,
            format: Some(OriginFormat::Dotenv),
            subkind: None,
        }
    }

    pub fn new_reference(file_path: Utf8PathBuf, line: Option<usize>, environment: Option<String>) -> Self {
        Self {
            file_path,
            line,
            kind: OriginKind::Reference,
            environment,
            format: Some(OriginFormat::Dotenv),
            subkind: None,
        }
    }

    pub fn new_usage(file_path: Utf8PathBuf, line: Option<usize>, format: OriginFormat) -> Self {
        Self {
            file_path,
            line,
            kind: OriginKind::Usage,
            environment: None,
            format: Some(format),
            subkind: None,
        }
    }

    pub fn with_subkind(mut self, subkind: String) -> Self {
        self.subkind = Some(subkind);
        self
    }
}