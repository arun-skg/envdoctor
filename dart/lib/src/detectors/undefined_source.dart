import '../models/finding.dart';
import 'detector.dart';

/// Undefined-in-source: a variable referenced as `process.env.X` /
/// `import.meta.env.X` in source code that is not defined in any environment
/// file and not documented in `.env.example`.
class UndefinedSourceDetector implements Detector {
  @override
  String get id => 'undefined-in-source';

  @override
  String get name => 'undefined-in-source';

  @override
  String get description =>
      'Used in source code but not defined in any environment file and not documented in .env.example.';

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];
    final defined = index.envDefinitions.keys.toSet();

    for (final entry in sortedEntries(index.sourceUsages, originSortKey)) {
      if (defined.contains(entry.key)) continue;
      findings.add(Finding.make(
        'undefined-in-source',
        Severity.error,
        entry.key,
        'used in source code but not defined in any environment file',
        entry.value,
      ));
    }

    return findings;
  }
}
