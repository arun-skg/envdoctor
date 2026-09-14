import Foundation

/// Build the default parser registry. Parsers are independent and ordered
/// most-specific first; discovery assigns each discovered file to the first
/// parser whose `match` claims it.
public func defaultRegistry(sourceExtensions: [String]) -> [Parser] {
    [
        EnvParser(),
        DockerComposeParser(),
        GithubActionsParser(),
        K8sParser(),
        SourceParser(extensions: sourceExtensions),
    ]
}
