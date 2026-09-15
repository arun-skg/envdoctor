/// Parser for docker-compose files.
///
/// Definitions come from `services.<name>.environment:` blocks (both the map
/// and the list form). Bare list entries (`- FOO`) become value-less
/// definitions. `$VAR` / `${VAR}` interpolation anywhere in the file becomes
/// usages.
library;

import '../models/environment_file.dart';
import '../models/environment_variable.dart';
import '../models/origin.dart';
import '../utils/paths.dart';
import 'parser.dart';
import 'yaml_facade.dart';
import 'yaml_interp.dart';

class DockerComposeParser implements Parser {
  static const Set<String> composeBasenames = {
    'docker-compose.yml',
    'docker-compose.yaml',
    'docker-compose.override.yml',
    'docker-compose.override.yaml',
    'compose.yml',
    'compose.yaml',
  };

  @override
  String get id => 'docker-compose';

  @override
  bool matchPath(String filePath) => composeBasenames.contains(basename(filePath));

  @override
  EnvironmentFile parse(String content, String filePath) {
    final doc = yamlLoadFirst(content);
    final variables = <EnvironmentVariable>[];

    if (doc is Map<String, Object?>) {
      final services = doc['services'];
      if (services is Map<String, Object?>) {
        for (final serviceValue in services.values) {
          Object? env;
          if (serviceValue is Map<String, Object?>) {
            env = serviceValue['environment'];
          }
          variables.addAll(_normalizeEnvironment(env, content, filePath));
        }
      }
    }

    // `$VAR` / `${VAR}` interpolation → usages.
    final usages = <EnvironmentVariable>[];
    for (final interp in scanInterpolations(content)) {
      final origin = Origin(
        filePath: filePath,
        line: interp.line,
        kind: OriginKind.usage,
        format: OriginFormat.dockerCompose,
      );
      usages.add(EnvironmentVariable.create(interp.name, null, [origin]));
    }

    return EnvironmentFile(
      filePath: filePath,
      format: FileFormat.dockerCompose,
      variables: EnvironmentVariable.merge(variables),
      usages: EnvironmentVariable.merge(usages),
    );
  }

  /// Flatten a service's `environment:` value into definition variables.
  List<EnvironmentVariable> _normalizeEnvironment(
      Object? env, String content, String filePath) {
    final variables = <EnvironmentVariable>[];
    if (env == null) return variables;

    if (env is Map<String, Object?>) {
      // Map form: KEY: value
      for (final entry in env.entries) {
        final key = entry.key;
        final rawValue = entry.value;
        final value = rawValue == null ? null : jsString(rawValue);
        final origin = Origin(
          filePath: filePath,
          line: _lineForName(content, key),
          kind: value == null ? OriginKind.reference : OriginKind.definition,
          format: OriginFormat.dockerCompose,
        );
        variables.add(EnvironmentVariable.create(key, value, [origin]));
      }
    } else if (env is List<Object?>) {
      // List form: - KEY=value | - KEY
      for (final item in env) {
        if (item is! String) continue;
        final trimmed = item.trim();
        if (trimmed.isEmpty) continue;
        final eq = trimmed.indexOf('=');
        String key;
        String? value;
        if (eq < 0) {
          key = trimmed;
          value = null;
        } else {
          key = trimmed.substring(0, eq);
          value = trimmed.substring(eq + 1);
        }
        final origin = Origin(
          filePath: filePath,
          line: _lineForName(content, key),
          kind: value == null ? OriginKind.reference : OriginKind.definition,
          format: OriginFormat.dockerCompose,
        );
        variables.add(EnvironmentVariable.create(key, value, [origin]));
      }
    }

    return variables;
  }

  /// Best-effort line lookup for a definition name in the raw YAML text.
  static int? _lineForName(String content, String name) {
    final escaped = RegExp.escape(name);
    // Supports both map form (`KEY: value`) and list form (`- KEY=value`).
    final re = RegExp('^\\s*[- ]*[""\']?$escaped[""\']?\\s*[:=]', multiLine: true);
    final match = re.firstMatch(content);
    return match == null ? null : lineForOffset(content, match.start);
  }
}
