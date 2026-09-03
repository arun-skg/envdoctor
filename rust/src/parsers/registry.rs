use crate::parsers::{docker_compose::DockerComposeParser, env::EnvParser, github_actions::GithubActionsParser, k8s::K8sParser, source::SourceParser, ParserRegistry};

pub struct RegistryOptions {
    pub source_extensions: Vec<String>,
}

/// Build the default parser registry. Parsers are independent and ordered
/// most-specific first; discovery assigns each discovered file to the first
/// parser whose `match` claims it.
pub fn default_registry(options: RegistryOptions) -> ParserRegistry {
    vec![
        Box::new(EnvParser),
        Box::new(DockerComposeParser),
        Box::new(GithubActionsParser),
        Box::new(K8sParser),
        Box::new(SourceParser::new(options.source_extensions)),
    ]
}