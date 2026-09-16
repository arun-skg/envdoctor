/// Assemble a [ProjectModel] from discovered file paths.
library;

import 'dart:io';

import '../config/config.dart';
import '../models/environment_file.dart';
import '../models/project_model.dart';
import '../parsers/parser.dart';
import '../utils/glob.dart';
import '../utils/paths.dart';

ProjectModel assembleModel(
    String rootDir, EnvdoctorConfig config, List<String> discovered) {
  final registry = defaultRegistry(config.sourceExtensions);
  final envFiles = <EnvironmentFile>[];
  final composeFiles = <EnvironmentFile>[];
  final actionFiles = <EnvironmentFile>[];
  final k8sFiles = <EnvironmentFile>[];
  final sourceFiles = <EnvironmentFile>[];
  final allFiles = <EnvironmentFile>[];
  final parseErrors = <ParseError>[];

  for (final path in discovered) {
    final String content;
    try {
      content = File(path).readAsStringSync();
    } catch (e) {
      parseErrors.add(ParseError(path, 'Cannot read file: $e'));
      continue;
    }

    // Skip if ignored by config.
    if (config.ignoreFiles.isNotEmpty) {
      final rel = relativeTo(rootDir, path);
      if (rel != null && matchesAnyGlob(config.ignoreFiles, rel)) continue;
    }

    EnvironmentFile? parsed;
    for (final parser in registry) {
      if (parser.matchPath(path)) {
        parsed = parser.parse(content, path);
        break;
      }
    }

    if (parsed != null) {
      switch (parsed.format) {
        case FileFormat.dotenv:
          envFiles.add(parsed);
        case FileFormat.dockerCompose:
          composeFiles.add(parsed);
        case FileFormat.githubActions:
          actionFiles.add(parsed);
        case FileFormat.kubernetes:
          k8sFiles.add(parsed);
        case FileFormat.source:
          sourceFiles.add(parsed);
      }
      allFiles.add(parsed);
    }
  }

  // Apply ignoreVariables to parsed variables.
  _applyIgnoreVariables(envFiles, config);
  _applyIgnoreVariables(composeFiles, config);
  _applyIgnoreVariables(actionFiles, config);
  _applyIgnoreVariables(k8sFiles, config);
  _applyIgnoreVariables(sourceFiles, config);

  // Apply environment overrides if configured.
  _applyEnvironmentOverrides(envFiles, rootDir, config);

  final model = ProjectModel(rootDir: rootDir, config: config)
    ..envFiles = envFiles
    ..composeFiles = composeFiles
    ..actionFiles = actionFiles
    ..k8sFiles = k8sFiles
    ..sourceFiles = sourceFiles
    ..allFiles = allFiles
    ..parseErrors = parseErrors;
  return model;
}

/// Remove variables whose names match `ignoreVariables` globs.
void _applyIgnoreVariables(List<EnvironmentFile> files, EnvdoctorConfig config) {
  if (config.ignoreVariables.isEmpty) return;
  for (final f in files) {
    f.variables
        .removeWhere((v) => matchesAnyGlob(config.ignoreVariables, v.name));
    f.usages.removeWhere((v) => matchesAnyGlob(config.ignoreVariables, v.name));
  }
}

/// If `environments` is configured, override the environment label for
/// files matching the given globs.
void _applyEnvironmentOverrides(
    List<EnvironmentFile> files, String rootDir, EnvdoctorConfig config) {
  final environments = config.environments;
  if (environments == null) return;
  for (final f in files) {
    final rel = relativeTo(rootDir, f.filePath) ?? f.filePath;
    for (final entry in environments.entries) {
      if (matchesAnyGlob(entry.value, rel)) {
        f.environment = entry.key;
        for (final v in f.variables) {
          for (final o in v.origins) {
            o.environment = entry.key;
          }
        }
        for (final v in f.usages) {
          for (final o in v.origins) {
            o.environment = entry.key;
          }
        }
        break;
      }
    }
  }
}
