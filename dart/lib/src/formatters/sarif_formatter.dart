import '../core/audit.dart';
import '../models/finding.dart';
import '../utils/json.dart';
import '../utils/paths.dart';

const String sarifSchema =
    'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json';

/// Detectors whose default severity is `error`; everything else defaults
/// to `warning`. Mirrors the reference `defaultLevelForDetector`.
const List<String> errorDetectors = [
  'missing',
  'undefined-in-source',
  'type-mismatch',
  'public-prefix',
];

/// Render findings as SARIF 2.1.0 for GitHub code scanning.
String renderSarif(List<Finding> findings, String rootDir) {
  final results = findings.map((f) => _findingToSarif(f, rootDir)).toList();

  return jsonPretty(JsonObject()
    ..add('\$schema', sarifSchema)
    ..add('version', '2.1.0')
    ..add('runs', [
      JsonObject()
        ..add('tool', JsonObject()
          ..add('driver', JsonObject()
            ..add('name', 'envdoctor')
            ..add('informationUri', 'https://github.com/arun-skg/envdoctor')
            ..add('rules', _renderRules())))
        ..add('results', results),
    ]));
}

String _severityToLevel(Severity severity) => switch (severity) {
      Severity.error => 'error',
      Severity.warning => 'warning',
      Severity.info => 'note',
    };

Object _findingToSarif(Finding f, String rootDir) {
  final locations = f.locations.map((o) {
    final rel = relativeTo(rootDir, o.filePath) ?? o.filePath;
    final physical = JsonObject()
      ..add('artifactLocation', JsonObject()
        ..add('uri', normalizePath(rel)));
    final line = o.line;
    if (line != null && line > 0) {
      physical.add('region', JsonObject()..add('startLine', line));
    }
    return JsonObject()..add('physicalLocation', physical);
  }).toList();

  return JsonObject()
    ..add('ruleId', f.ruleId)
    ..add('level', _severityToLevel(f.severity))
    ..add('message', JsonObject()..add('text', '${f.variable}: ${f.message}'))
    ..add('locations', locations);
}

/// The full detector catalog, matching the reference CLI (all rules appear,
/// not only the ones with findings).
List<Object> _renderRules() => allDetectors().map((d) {
      final level = errorDetectors.contains(d.id) ? 'error' : 'warning';
      return JsonObject()
        ..add('id', d.id)
        ..add('name', d.name)
        ..add('shortDescription', JsonObject()..add('text', d.description))
        ..add('defaultConfiguration', JsonObject()..add('level', level));
    }).toList();
