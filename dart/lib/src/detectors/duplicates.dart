import '../models/finding.dart';
import '../models/origin.dart';
import 'detector.dart';

/// Duplicates: the same variable defined more than once within a single file.
/// dotenv applies last-wins, so a repeated key is a silent override that
/// usually means a merge conflict or a copy-paste bug.
class DuplicatesDetector implements Detector {
  @override
  String get id => 'duplicates';

  @override
  String get name => 'duplicates';

  @override
  String get description =>
      'The same variable is defined more than once in a single file.';

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];

    for (final file in index.model.envFiles) {
      final byName = <String, List<Origin>>{};
      final order = <String>[];
      for (final v in file.variables) {
        if (!byName.containsKey(v.name)) order.add(v.name);
        byName.putIfAbsent(v.name, () => []).addAll(v.origins);
      }

      for (final name in order) {
        final origins = byName[name]!;
        if (origins.length < 2) continue;
        final lines = origins.where((o) => o.line != null).map((o) => o.line!).toList();
        final where = lines.isNotEmpty ? 'on lines ${lines.join(', ')}' : 'in this file';
        findings.add(Finding.make(
          'duplicates',
          Severity.error,
          name,
          'defined ${origins.length} times $where',
          origins,
        ));
      }
    }

    return findings;
  }
}
