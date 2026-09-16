import '../config/config.dart';
import '../models/environment_file.dart';
import '../models/environment_variable.dart';
import '../models/origin.dart';

/// A normalized view of one environment variable across every file in the
/// project.
class ProjectModel {
  final String rootDir;
  EnvdoctorConfig config;
  List<EnvironmentFile> envFiles = [];
  List<EnvironmentFile> composeFiles = [];
  List<EnvironmentFile> actionFiles = [];
  List<EnvironmentFile> k8sFiles = [];
  List<EnvironmentFile> sourceFiles = [];
  List<EnvironmentFile> allFiles = [];
  List<ParseError> parseErrors = [];

  ProjectModel({required this.rootDir, EnvdoctorConfig? config})
      : config = config ?? EnvdoctorConfig();

  /// All definitions (variables with values) across the whole project.
  Iterable<EnvironmentVariable> allDefinitions() sync* {
    for (final f in envFiles) {
      yield* f.variables;
    }
    for (final f in composeFiles) {
      yield* f.variables;
    }
    for (final f in actionFiles) {
      yield* f.variables;
    }
  }

  /// All usages (name references without values) across the whole project.
  Iterable<EnvironmentVariable> allUsages() sync* {
    for (final f in envFiles) {
      yield* f.usages;
    }
    for (final f in composeFiles) {
      yield* f.usages;
    }
    for (final f in actionFiles) {
      yield* f.usages;
    }
    for (final f in sourceFiles) {
      yield* f.usages;
    }
  }

  /// Flatten every origin for a name into a deduplicated list.
  List<Origin> originsForName(String name) {
    final seen = <String, Origin>{};
    for (final file in allFiles) {
      for (final v in [...file.variables, ...file.usages]) {
        if (v.name != name) continue;
        for (final origin in v.origins) {
          final key = '${origin.filePath}:${origin.line}:${origin.kind}';
          seen.putIfAbsent(key, () => Origin.clone(origin));
        }
      }
    }
    return seen.values.toList();
  }
}

class ParseError {
  final String filePath;
  final String error;
  ParseError(this.filePath, this.error);
}
