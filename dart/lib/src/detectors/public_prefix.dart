import '../models/environment_variable.dart';
import '../models/finding.dart';
import 'detector.dart';

/// Public-prefix leak: variables whose names match the secret heuristic but
/// use a framework prefix that exposes them to client-side bundles.
class PublicPrefixDetector implements Detector {
  static const List<String> publicPrefixes = [
    'NEXT_PUBLIC_',
    'VITE_',
    'PUBLIC_',
    'REACT_APP_',
    'GATSBY_',
    'EXPO_PUBLIC_',
    'NUXT_PUBLIC_',
    'ASTRO_PUBLIC_',
  ];

  @override
  String get id => 'public-prefix';

  @override
  String get name => 'public-prefix';

  @override
  String get description =>
      'A secret-looking variable uses a public framework prefix and will be exposed to client bundles.';

  static String? findPublicPrefix(String name) {
    for (final prefix in publicPrefixes) {
      if (name.startsWith(prefix)) return prefix;
    }
    return null;
  }

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];

    for (final entry in sortedEntries(index.envDefinitions, defSortKey)) {
      final prefix = findPublicPrefix(entry.key);
      if (prefix == null) continue;
      if (!EnvironmentVariable.isSecretName(entry.key)) continue;
      findings.add(Finding.make(
        'public-prefix',
        Severity.error,
        entry.key,
        '${entry.key} uses public prefix "$prefix"; secret-looking variables with this prefix are exposed to client bundles',
        entry.value.map((d) => d.origin).toList(),
      ));
    }

    return findings;
  }
}
