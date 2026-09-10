using Envdoctor.Models;

namespace Envdoctor.Parsers;

/// A parser turns the raw text of one supported file format into envdoctor's
/// normalized `EnvironmentFile`. A parser must never throw on malformed input.
public interface IParser
{
    string Id { get; }
    bool MatchPath(string filePath);
    EnvironmentFile Parse(string content, string filePath);
}

/// Ordered list of parsers, most specific first.
public static class ParserRegistry
{
    public static List<IParser> DefaultRegistry(IReadOnlyList<string> sourceExtensions) =>
        new()
        {
            new EnvParser(),
            new DockerComposeParser(),
            new GithubActionsParser(),
            new K8sParser(),
            new SourceParser(sourceExtensions),
        };

    /// Match a path against a registry; returns the first parser that claims it.
    public static IParser? ParserForPath(IReadOnlyList<IParser> registry, string filePath) =>
        registry.FirstOrDefault(p => p.MatchPath(filePath));
}
