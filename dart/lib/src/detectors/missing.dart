import '../models/finding.dart';
import '../models/origin.dart';
import 'detector.dart';

/// Missing: a variable that is referenced (in docker-compose, GitHub Actions,
/// or `.env.example`) but defined in no environment file. Source-code
/// references are the concern of the `undefined-in-source` detector.
class MissingDetector implements Detector {
  @override
  String get id => 'missing';

  @override
  String get name => 'missing';

  @override
  String get description =>
      'Referenced in docker-compose, GitHub Actions, or .env.example but not defined in any environment file.';

  @override
  List<Finding> detect(IndexedModel index) {
    final findings = <Finding>[];
    final defined = index.envDefinitions.keys.toSet();
    // Source usages are the undefined-in-source detector's job — skipping them
    // here avoids double-reporting a variable that is used in source code and
    // also referenced in compose/actions/.env.example.
    final sourceUsed = index.sourceUsages.keys.toSet();
    final seen = <String>{};

    // Built in the same three phases as the reference CLI (compose defs,
    // then .env.example names, then compose `${VAR}` interpolations) so the
    // emission order matches.
    final referenced = <(String, List<Origin>)>[];

    // Compose definitions that are NOT in any .env file are "missing".
    for (final entry in sortedEntries(index.composeDefinitions, defSortKey)) {
      if (!defined.contains(entry.key) && !sourceUsed.contains(entry.key)) {
        referenced.add((entry.key, entry.value.map((d) => d.origin).toList()));
      }
    }

    // .env.example names that are NOT in any .env file are "missing".
    for (final name in index.exampleNames) {
      if (!defined.contains(name) && !sourceUsed.contains(name)) {
        referenced.add((name, []));
      }
    }

    // `${VAR}` interpolation in docker-compose means compose expects the
    // variable to exist. GitHub Actions `secrets.X`/`vars.X` references are
    // intentionally NOT checked here.
    for (final entry in sortedEntries(index.usages, originSortKey)) {
      final composeOrigins = entry.value
          .where((o) => o.format == OriginFormat.dockerCompose)
          .toList();
      if (composeOrigins.isEmpty) continue;
      if (defined.contains(entry.key) || sourceUsed.contains(entry.key)) continue;
      referenced.add((entry.key, composeOrigins));
    }

    for (final (name, origins) in referenced) {
      if (seen.add(name)) {
        findings.add(Finding.make(
          'missing',
          Severity.error,
          name,
          'referenced but not defined in any environment file',
          origins,
        ));
      }
    }

    return findings;
  }
}
