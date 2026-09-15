import '../models/finding.dart';
import '../models/origin.dart';
import 'detector.dart';

/// Typo detector: pairs names that are referenced but not defined with names
/// that are defined but not referenced, and have a small edit distance.
class TypoDetector implements Detector {
  @override
  String get id => 'typo';

  @override
  String get name => 'typo';

  @override
  String get description =>
      'A referenced variable name is very similar to a defined variable name and may be a typo.';

  static int levenshtein(String a, String b) {
    final matrix = List.generate(b.length + 1, (i) => List.filled(a.length + 1, 0));
    for (var i = 0; i <= b.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= a.length; j++) {
      matrix[0][j] = j;
    }
    for (var i = 1; i <= b.length; i++) {
      for (var j = 1; j <= a.length; j++) {
        final cost = b.codeUnitAt(i - 1) == a.codeUnitAt(j - 1) ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return matrix[b.length][a.length];
  }

  /// Earliest (file, line) a name is referenced at, across usages and
  /// compose/action definitions.
  static SortKey _referenceSortKey(IndexedModel index, String name) {
    final origins = <Origin>[];
    origins.addAll(index.usages[name] ?? []);
    for (final d in index.composeDefinitions[name] ?? []) {
      origins.add(d.origin);
    }
    for (final d in index.actionDefinitions[name] ?? []) {
      origins.add(d.origin);
    }
    return originSortKey(origins);
  }

  static bool isLikelyTypo(String a, String b) {
    if (a == b) return false;
    if (a.length < 4 || b.length < 4) return false;
    final distance = levenshtein(a, b);
    final minLen = a.length < b.length ? a.length : b.length;
    // Distance of 1 is always flagged for names >= 4 chars.
    // Distance of 2 is flagged for names >= 6 chars.
    // Larger distances only when names are long.
    if (distance == 1) return true;
    if (distance == 2) return minLen >= 6;
    if (distance == 3) return minLen >= 10;
    return false;
  }

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];

    final defined = index.envDefinitions.keys.toSet();
    final used = <String>{
      ...index.usages.keys,
      ...index.composeDefinitions.keys,
      ...index.actionDefinitions.keys,
    };

    // Names referenced but not defined anywhere, ordered by where they are
    // first referenced (usages, then compose/action defs).
    final undefinedNames = used.where((n) => !defined.contains(n)).toList();
    undefinedNames.sort((a, b) {
      final cmp = compareKeys(_referenceSortKey(index, a), _referenceSortKey(index, b));
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    // Names defined but never referenced anywhere, ordered by parse order.
    final unusedNames = index.envDefinitions.keys.where((n) => !used.contains(n)).toList();
    unusedNames.sort((a, b) {
      final cmp = compareKeys(
        defSortKey(index.envDefinitions[a]!),
        defSortKey(index.envDefinitions[b]!),
      );
      return cmp != 0 ? cmp : a.compareTo(b);
    });

    final seen = <String>{};

    for (final undefinedName in undefinedNames) {
      for (final unusedName in unusedNames) {
        if (!isLikelyTypo(undefinedName, unusedName)) continue;
        final pairNames = [undefinedName, unusedName]..sort();
        final pairKey = pairNames.join('\x00');
        if (seen.add(pairKey)) {
          final origins = (index.usages[undefinedName] ?? []).take(3).toList();
          findings.add(Finding.make(
            'typo',
            Severity.warning,
            undefinedName,
            'did you mean "$unusedName"? ($undefinedName is referenced but not defined, $unusedName is defined but unused)',
            origins,
          ));
        }
      }
    }

    return findings;
  }
}
