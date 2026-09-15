import 'environment_variable.dart';

enum FileFormat {
  dotenv,
  dockerCompose,
  githubActions,
  kubernetes,
  source;

  String get str => switch (this) {
        FileFormat.dotenv => 'dotenv',
        FileFormat.dockerCompose => 'docker-compose',
        FileFormat.githubActions => 'github-actions',
        FileFormat.kubernetes => 'kubernetes',
        FileFormat.source => 'source',
      };
}

/// The parsed contents of a single file, normalized to envdoctor's model.
class EnvironmentFile {
  final String filePath;
  final FileFormat format;
  String? environment;
  List<EnvironmentVariable> variables;
  List<EnvironmentVariable> usages;

  EnvironmentFile({
    required this.filePath,
    required this.format,
    this.environment,
    List<EnvironmentVariable>? variables,
    List<EnvironmentVariable>? usages,
  })  : variables = variables ?? [],
        usages = usages ?? [];

  /// Names defined in a file, deduplicated, in first-seen order.
  List<String> definedNames() {
    final seen = <String>{};
    final result = <String>[];
    for (final v in variables) {
      if (seen.add(v.name)) result.add(v.name);
    }
    return result;
  }

  /// Names used in a file, deduplicated, in first-seen order.
  List<String> usedNames() {
    final seen = <String>{};
    final result = <String>[];
    for (final v in usages) {
      if (seen.add(v.name)) result.add(v.name);
    }
    return result;
  }
}
