import 'dart:io';

import '../models/project_model.dart';
import '../utils/paths.dart';

final stdoutBuffer = stdout;
final stderrBuffer = stderr;

void out(String s) => stdout.write(s);
void err(String s) => stderr.write(s);

/// Report files that could not be parsed, without failing the command.
void reportParseErrors(ProjectModel model, String rootDir) {
  for (final pe in model.parseErrors) {
    err('⚠ ${displayPath(rootDir, pe.filePath)}: ${pe.error}\n');
  }
}

/// The normalized environment label for a user-supplied diff/sync argument.
String normalizeEnvLabel(String label) {
  final trimmed = label.trim();
  if (trimmed == 'dev') return 'development';
  if (trimmed == 'prod') return 'production';
  return trimmed;
}
