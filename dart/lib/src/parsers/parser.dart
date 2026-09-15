import '../models/environment_file.dart';
import 'docker_compose_parser.dart';
import 'env_parser.dart';
import 'github_actions_parser.dart';
import 'k8s_parser.dart';
import 'source_parser.dart';

/// A parser turns the raw text of one supported file format into envdoctor's
/// normalized `EnvironmentFile`. A parser must never throw on malformed input.
abstract class Parser {
  String get id;
  bool matchPath(String filePath);
  EnvironmentFile parse(String content, String filePath);
}

/// Ordered list of parsers, most specific first.
List<Parser> defaultRegistry(List<String> sourceExtensions) => [
      EnvParser(),
      DockerComposeParser(),
      GithubActionsParser(),
      K8sParser(),
      SourceParser(sourceExtensions),
    ];

/// Match a path against a registry; returns the first parser that claims it.
Parser? parserForPath(List<Parser> registry, String filePath) {
  for (final p in registry) {
    if (p.matchPath(filePath)) return p;
  }
  return null;
}
