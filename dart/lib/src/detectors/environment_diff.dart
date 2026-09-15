import '../models/finding.dart';
import '../models/project_model.dart';
import '../utils/locale.dart';
import 'detector.dart';

class EnvDiffEntry {
  final String name;
  final bool presentInBoth;
  final bool presentInA;
  final bool presentInB;

  EnvDiffEntry({
    required this.name,
    required this.presentInBoth,
    required this.presentInA,
    required this.presentInB,
  });
}

/// Environment-diff: a variable exists in one environment file but is missing
/// from another.
class EnvironmentDiffDetector implements Detector {
  @override
  String get id => 'environment-diff';

  @override
  String get name => 'environment-diff';

  @override
  String get description =>
      'A variable exists in one environment file but is missing from another.';

  /// The set of variable names defined for a given environment label.
  static Set<String> variablesForEnvironment(ProjectModel model, String label) {
    final names = <String>{};
    for (final file in model.envFiles) {
      if (file.environment == label) {
        for (final v in file.variables) {
          names.add(v.name);
        }
      }
    }
    return names;
  }

  /// Compare two environment labels, returning one entry per variable.
  static List<EnvDiffEntry> compareEnvironments(
      ProjectModel model, String labelA, String labelB) {
    final a = variablesForEnvironment(model, labelA);
    final b = variablesForEnvironment(model, labelB);
    final all = <String>{...a, ...b}.toList();
    final entries = all
        .map((name) => EnvDiffEntry(
              name: name,
              presentInA: a.contains(name),
              presentInB: b.contains(name),
              presentInBoth: a.contains(name) && b.contains(name),
            ))
        .toList();
    // Match the TS reference, which orders by `localeCompare`, not byte order.
    entries.sort((x, y) => localeCompare(x.name, y.name));
    return entries;
  }

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];
    final labels = index.envLabels;
    if (labels.length < 2) return findings;
    final reference =
        labels.contains('development') ? 'development' : labels.first;

    for (final other in labels) {
      if (other == reference) continue;
      for (final entry in compareEnvironments(index.model, reference, other)) {
        if (entry.presentInBoth) continue;
        final missingIn = entry.presentInA ? other : reference;
        findings.add(Finding.make(
          'environment-diff',
          Severity.warning,
          entry.name,
          '$reference → $other · ${entry.name} missing in $missingIn',
          [],
        ));
      }
    }

    return findings;
  }
}
