/// Parser for Kubernetes manifests.
///
/// Matches YAML files that look like Kubernetes resources (have apiVersion and
/// kind). Extracts container environment definitions and `${VAR}` / `$VAR`
/// interpolations from command/args/env values.
library;

import '../models/environment_file.dart';
import '../models/environment_variable.dart';
import '../models/origin.dart';
import '../utils/paths.dart';
import 'parser.dart';
import 'yaml_facade.dart';
import 'yaml_interp.dart';

class K8sParser implements Parser {
  @override
  String get id => 'kubernetes';

  @override
  bool matchPath(String filePath) {
    final ext = extensionOf(filePath).toLowerCase();
    return ext == 'yaml' || ext == 'yml';
  }

  @override
  EnvironmentFile parse(String content, String filePath) {
    final docArray = yamlLoadAll(content);

    final variables = <EnvironmentVariable>[];
    final usages = <EnvironmentVariable>[];

    for (final doc in docArray) {
      if (!_looksLikeK8s(doc)) continue;
      _walkResource(doc as Map<String, Object?>, filePath, variables, usages);
    }

    return EnvironmentFile(
      filePath: filePath,
      format: FileFormat.kubernetes,
      variables: EnvironmentVariable.merge(variables),
      usages: EnvironmentVariable.merge(usages),
    );
  }

  static bool _looksLikeK8s(Object? doc) =>
      doc is Map<String, Object?> &&
      doc['apiVersion'] is String &&
      doc['kind'] is String;

  static Origin _originAt(String filePath, int? line,
          {OriginKind kind = OriginKind.definition}) =>
      Origin(filePath: filePath, line: line, kind: kind, format: OriginFormat.kubernetes);

  static Map<String, Object?>? _getObject(Map<String, Object?> obj, String key) {
    final value = obj[key];
    return value is Map<String, Object?> ? value : null;
  }

  static List<Object?>? _getArray(Map<String, Object?> obj, String key) {
    final value = obj[key];
    return value is List<Object?> ? value : null;
  }

  static void _walkResource(Map<String, Object?> doc, String filePath,
      List<EnvironmentVariable> variables, List<EnvironmentVariable> usages) {
    final kind = doc['kind'] as String?;

    // ConfigMap data keys become definitions.
    if (kind == 'ConfigMap') {
      final data = _getObject(doc, 'data');
      if (data != null) {
        for (final entry in data.entries) {
          if (entry.value is! String || entry.key.isEmpty) continue;
          variables.add(EnvironmentVariable.create(
              entry.key, entry.value as String, [_originAt(filePath, null)]));
        }
      }
      return;
    }

    final spec = _getObject(doc, 'spec');
    if (spec == null) return;

    final template = _getObject(spec, 'template');
    final podSpec = template != null ? _getObject(template, 'spec') : spec;
    if (podSpec == null) return;

    final containers = <Object?>[
      ...?_getArray(podSpec, 'containers'),
      ...?_getArray(podSpec, 'initContainers'),
    ];

    for (final container in containers) {
      if (container is! Map<String, Object?>) continue;

      for (final raw in _getArray(container, 'env') ?? <Object?>[]) {
        if (raw is! Map<String, Object?>) continue;
        final nameObj = raw['name'];
        if (nameObj is! String || nameObj.isEmpty) continue;
        final value = raw['value'];
        if (value is String) {
          variables.add(EnvironmentVariable.create(
              nameObj, value, [_originAt(filePath, null)]));
        } else if (raw.containsKey('valueFrom')) {
          // Referenced but value provided elsewhere (ConfigMap/Secret).
          usages.add(EnvironmentVariable.create(
              nameObj, null, [_originAt(filePath, null, kind: OriginKind.usage)]));
        }
      }

      for (final raw in _getArray(container, 'envFrom') ?? <Object?>[]) {
        if (raw is! Map<String, Object?>) continue;
        final prefixObj = raw['prefix'];
        final prefix = prefixObj is String ? prefixObj : '';
        final configMapRef = _getObject(raw, 'configMapRef');
        if (configMapRef != null && configMapRef['name'] is String) {
          usages.add(EnvironmentVariable.create(
              '$prefix*', null, [_originAt(filePath, null, kind: OriginKind.usage)]));
        }
        final secretRef = _getObject(raw, 'secretRef');
        if (secretRef != null && secretRef['name'] is String) {
          usages.add(EnvironmentVariable.create(
              '$prefix*', null, [_originAt(filePath, null, kind: OriginKind.usage)]));
        }
      }

      // Interpolations in command/args.
      for (final key in ['command', 'args']) {
        final list = _getArray(container, key);
        if (list == null) continue;
        for (final item in list) {
          if (item is! String) continue;
          for (final interp in scanInterpolations(item)) {
            usages.add(EnvironmentVariable.create(
                interp.name, null, [_originAt(filePath, interp.line, kind: OriginKind.usage)]));
          }
        }
      }
    }
  }
}
