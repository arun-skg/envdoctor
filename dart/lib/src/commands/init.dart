/// `envdoctor init` — bootstrap envdoctor for a project. Non-destructive:
/// existing files are only overwritten with `--force`.
library;

import 'dart:io';

import '../core/pipeline.dart';
import '../generators/env_example.dart';
import '../generators/environment_doc.dart';
import '../utils/paths.dart';
import 'shared.dart';

class InitOptions {
  final String rootDir;
  final bool force;

  InitOptions({required this.rootDir, this.force = false});
}

const String configTemplate = '''
// envdoctor configuration (optional).
// See https://github.com/arun-skg/envdoctor for the full reference.
export default {
  // Glob patterns for dotenv files.
  // envFilePatterns: [".env", ".env.*"],
  // File extensions scanned for process.env usage.
  // sourceExtensions: ["ts", "tsx", "js", "jsx", "mjs", "cjs"],
  // Variable names to never report (globs supported).
  // ignoreVariables: ["AWS_*"],
  // Fail the audit on warnings too.
  // strict: false,
};
''';

const String configBasename = 'envdoctor.config.mjs';

int runInit(InitOptions opts) {
  final context = loadProject(opts.rootDir);

  final created = <String>[];
  final skipped = <String>[];

  void writeIfAbsent(String relPath, String content) {
    final full = joinPath(opts.rootDir, relPath);
    if (File(full).existsSync() && !opts.force) {
      skipped.add(relPath);
      return;
    }
    Directory(dirname(full)).createSync(recursive: true);
    File(full).writeAsStringSync(content);
    created.add(relPath);
  }

  writeIfAbsent(configBasename, configTemplate);
  writeIfAbsent('.env.example', generateEnvExample(context.model, context.config));
  writeIfAbsent('ENVIRONMENT.md', generateEnvironmentDoc(context.model, context.config));

  out('envdoctor init\n\n');
  for (final rel in created) {
    out('  ✓ created $rel\n');
  }
  for (final rel in skipped) {
    out('  · exists, skipped $rel (use --force to overwrite)\n');
  }
  out('\n  ${created.length} created, ${skipped.length} skipped\n');

  return 0;
}
