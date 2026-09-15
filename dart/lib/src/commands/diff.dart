/// `envdoctor diff <env1> <env2>` — compare variable sets across environments.
library;

import '../core/pipeline.dart';
import '../detectors/environment_diff.dart';
import '../utils/json.dart';
import 'shared.dart';

class DiffOptions {
  final String rootDir;
  final String envA;
  final String envB;
  final bool json;

  DiffOptions({
    required this.rootDir,
    required this.envA,
    required this.envB,
    this.json = false,
  });
}

int runDiff(DiffOptions opts) {
  final context = loadProject(opts.rootDir);
  final labelA = normalizeEnvLabel(opts.envA);
  final labelB = normalizeEnvLabel(opts.envB);

  final available = <String>{};
  for (final f in context.model.envFiles) {
    if (f.environment != null && f.environment != 'example') {
      available.add(f.environment!);
    }
  }

  reportParseErrors(context.model, opts.rootDir);

  if (!available.contains(labelA) || !available.contains(labelB)) {
    if (!available.contains(labelA)) {
      err('error Environment "$labelA" has no files in this project.\n');
    }
    if (!available.contains(labelB)) {
      err('error Environment "$labelB" has no files in this project.\n');
    }
    err('  Available: ${available.isEmpty ? 'none' : available.join(', ')}\n');
    return 2;
  }

  final entries = EnvironmentDiffDetector.compareEnvironments(
      context.model, labelA, labelB);
  final missingCount = entries.where((e) => !e.presentInBoth).length;

  if (opts.json) {
    final variables = entries
        .map((e) => JsonObject()
          ..add('name', e.name)
          ..add('status', e.presentInBoth ? 'same' : 'missing')
          ..add('missingIn',
              e.presentInBoth ? null : (e.presentInA ? labelB : labelA)))
        .toList();
    final payload = JsonObject()
      ..add('environments', [labelA, labelB])
      ..add('exitCode', missingCount > 0 ? 1 : 0)
      ..add('total', entries.length)
      ..add('missing', missingCount)
      ..add('variables', variables);
    out('${jsonPretty(payload)}\n');
    return missingCount > 0 ? 1 : 0;
  }

  out('ENVIRONMENT DIFF\n');
  out('${'─' * ('ENVIRONMENT DIFF'.length * 2)}\n\n');
  out('  $labelA → $labelB\n\n');

  for (final entry in entries) {
    if (entry.presentInBoth) {
      out('  ✓ ${entry.name}  present in both\n');
    } else if (entry.presentInA) {
      out('  ❌ ${entry.name}  missing in $labelB\n');
    } else {
      out('  ❌ ${entry.name}  missing in $labelA\n');
    }
  }
  out(
      '\n  Summary: ${entries.length} variables · $missingCount missing · ${entries.length - missingCount} present in both\n');

  return missingCount > 0 ? 1 : 0;
}
