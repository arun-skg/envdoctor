import '../models/finding.dart';
import 'detector.dart';

/// Weak/placeholder secret detector. Only inspects definitions in actual
/// environment files, never `.env.example`.
class WeakSecretDetector implements Detector {
  static const Set<String> blocklist = {
    '',
    'changeme',
    'password',
    'password123',
    'secret',
    'secret123',
    'token',
    'key',
    'apikey',
    'api_key',
    'test',
    'testing',
    '12345678',
    '123456789',
    '1234567890',
    'your_secret',
    'your_token',
    'your_api_key',
    'your_password',
    'example',
    'dummy',
    'foo',
    'bar',
    'admin',
    'default',
    'null',
    'undefined',
  };

  @override
  String get id => 'weak-secret';

  @override
  String get name => 'weak-secret';

  @override
  String get description =>
      'A secret-looking variable in an environment file has a weak or placeholder value.';

  static bool isWeakSecret(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (blocklist.contains(trimmed.toLowerCase())) return true;
    return trimmed.length < 8;
  }

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];

    for (final entry in sortedEntries(index.envDefinitions, defSortKey)) {
      for (final def in entry.value) {
        if (!def.isSecret) continue;
        if (def.value == null || !isWeakSecret(def.value!)) continue;
        final location =
            def.origin.line != null ? '${def.origin.filePath}:${def.origin.line}' : def.origin.filePath;
        findings.add(Finding.make(
          'weak-secret',
          Severity.warning,
          entry.key,
          '${entry.key} has a weak or placeholder value in $location',
          [def.origin],
        ));
      }
    }

    return findings;
  }
}
