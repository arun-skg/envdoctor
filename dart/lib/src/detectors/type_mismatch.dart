import '../models/finding.dart';
import '../models/variable_type.dart';
import 'detector.dart';

/// Type mismatch: the same variable is defined with values of incompatible
/// inferred types across environment files. The "expected" type is taken from
/// the development file when present, otherwise the most common type. Only
/// variable *types* and locations are reported — never values.
class TypeMismatchDetector implements Detector {
  @override
  String get id => 'type-mismatch';

  @override
  String get name => 'type-mismatch';

  @override
  String get description =>
      'The same variable has incompatible inferred types across environment files.';

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];

    for (final entry in sortedEntries(index.envDefinitions, defSortKey)) {
      final typed = entry.value
          .where((d) =>
              d.value != null &&
              d.type != VariableType.unknown &&
              d.value!.isNotEmpty)
          .toList();
      if (typed.length < 2) continue;

      final distinctTypes = typed.map((d) => d.type).toSet();
      if (distinctTypes.length < 2) continue;

      VariableType? devType;
      for (final d in typed) {
        if (d.environment == 'development') {
          devType = d.type;
          break;
        }
      }
      final resolvedExpected = devType ?? _mostCommonType(typed);

      for (final def in typed) {
        if (def.type == resolvedExpected) continue;
        findings.add(Finding.make(
          'type-mismatch',
          Severity.error,
          entry.key,
          'expected: ${resolvedExpected.str}, found: ${def.type.str}',
          [def.origin],
        ));
      }
    }

    return findings;
  }

  static VariableType _mostCommonType(List<Definition> defs) {
    // Count occurrences but resolve ties by first-seen order, matching the
    // reference CLI.
    final counts = <VariableType, int>{};
    final order = <VariableType>[];
    for (final d in defs) {
      if (!counts.containsKey(d.type)) order.add(d.type);
      counts[d.type] = (counts[d.type] ?? 0) + 1;
    }
    var best = order.first;
    var bestCount = -1;
    for (final ty in order) {
      final count = counts[ty]!;
      if (count > bestCount) {
        best = ty;
        bestCount = count;
      }
    }
    return best;
  }
}
