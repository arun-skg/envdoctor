import '../models/finding.dart';
import 'detector.dart';

/// Unused: a variable defined in an environment file that is never referenced
/// anywhere. `.env.example` contents are documentation and are excluded here.
class UnusedDetector implements Detector {
  @override
  String get id => 'unused';

  @override
  String get name => 'unused';

  @override
  String get description =>
      'Defined in an environment file but never referenced in source, docker-compose, GitHub Actions, or Kubernetes manifests.';

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];
    final used = <String>{...index.usages.keys};
    // A variable that is re-defined in compose/actions/k8s is, by definition, used.
    used.addAll(index.composeDefinitions.keys);
    used.addAll(index.actionDefinitions.keys);
    used.addAll(index.k8sDefinitions.keys);

    // Iterate in a stable file/line order so output is deterministic and
    // matches the reference CLI.
    final seen = <String>{};
    for (final entry in sortedEntries(index.envDefinitions, defSortKey)) {
      if (!seen.add(entry.key)) continue;
      if (used.contains(entry.key)) continue;
      findings.add(Finding.make(
        'unused',
        Severity.warning,
        entry.key,
        'defined but never referenced',
        entry.value.map((d) => d.origin).toList(),
      ));
    }

    return findings;
  }
}
