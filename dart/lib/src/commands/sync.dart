/// `envdoctor sync <from> <to>` — copy missing variable keys from one
/// environment file to another, using placeholder values. Never copies real
/// secret values.
library;

import 'dart:io';

import '../config/config.dart';
import '../core/pipeline.dart';
import '../models/environment_file.dart';
import '../models/environment_variable.dart';
import '../utils/paths.dart';
import 'shared.dart';

class SyncOptions {
  final String rootDir;
  final String envA;
  final String envB;
  final bool dryRun;

  SyncOptions({
    required this.rootDir,
    required this.envA,
    required this.envB,
    this.dryRun = false,
  });
}

int runSync(SyncOptions opts) {
  final fromLabel = normalizeEnvLabel(opts.envA);
  final toLabel = normalizeEnvLabel(opts.envB);

  final context = loadProject(opts.rootDir);
  final model = context.model;

  final fromNames = _namesForEnvironment(model.envFiles, fromLabel);
  final toNames = _namesForEnvironment(model.envFiles, toLabel);

  final missing =
      fromNames.where((n) => !toNames.contains(n)).toList()..sort();
  if (missing.isEmpty) {
    out('✓ $fromLabel → $toLabel: nothing to sync\n');
    return 0;
  }

  final targetFile = _targetEnvPath(opts.rootDir, toLabel, context.config);
  final targetRel = displayPath(opts.rootDir, targetFile);

  final lines = <String>['', '# Synced from $fromLabel by envdoctor'];
  for (final name in missing) {
    final placeholder =
        EnvironmentVariable.isSecretName(name) ? '' : 'your_${name.toLowerCase()}';
    lines.add('$name=$placeholder');
  }
  final append = '${lines.join('\n')}\n';

  if (opts.dryRun) {
    out('envdoctor sync (dry run)\n\n');
    out('Would append ${missing.length} key${missing.length == 1 ? '' : 's'} to $targetRel:\n');
    for (final name in missing) {
      out('  + $name\n');
    }
    return 0;
  }

  Directory(dirname(targetFile)).createSync(recursive: true);
  File(targetFile).writeAsStringSync(append, mode: FileMode.append);

  out('envdoctor sync\n\n');
  out('  ✓ Appended ${missing.length} key${missing.length == 1 ? '' : 's'} to $targetRel\n');
  for (final name in missing) {
    out('    + $name\n');
  }

  return 0;
}

Set<String> _namesForEnvironment(List<EnvironmentFile> envFiles, String label) {
  final names = <String>{};
  for (final file in envFiles) {
    if (file.environment == label) {
      for (final v in file.variables) {
        names.add(v.name);
      }
    }
  }
  return names;
}

String _targetEnvPath(String rootDir, String label, EnvdoctorConfig config) {
  final environments = config.environments;
  final files = environments?[label];
  if (files != null && files.isNotEmpty) {
    final f = files.first;
    return isAbsolutePath(f) ? f : joinPath(rootDir, f);
  }
  return label == 'development' ? joinPath(rootDir, '.env') : joinPath(rootDir, '.env.$label');
}
