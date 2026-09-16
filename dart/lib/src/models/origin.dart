/// Where a variable name was seen, and in what role. Values are intentionally
/// NOT carried here.
class Origin {
  final String filePath;
  final int? line;
  final OriginKind kind;
  String? environment;
  final OriginFormat? format;
  final String? subkind;

  Origin({
    required this.filePath,
    this.line,
    required this.kind,
    this.environment,
    this.format,
    this.subkind,
  });

  Origin.clone(Origin other)
      : filePath = other.filePath,
        line = other.line,
        kind = other.kind,
        environment = other.environment,
        format = other.format,
        subkind = other.subkind;

  Origin withSubkind(String value) => Origin(
        filePath: filePath,
        line: line,
        kind: kind,
        environment: environment,
        format: format,
        subkind: value,
      );

  static Origin newDefinition(String filePath, int? line, String? environment) =>
      Origin(
          filePath: filePath,
          line: line,
          kind: OriginKind.definition,
          environment: environment,
          format: OriginFormat.dotenv);

  static Origin newReference(String filePath, int? line, String? environment) =>
      Origin(
          filePath: filePath,
          line: line,
          kind: OriginKind.reference,
          environment: environment,
          format: OriginFormat.dotenv);

  static Origin newUsage(String filePath, int? line, OriginFormat format) =>
      Origin(filePath: filePath, line: line, kind: OriginKind.usage, format: format);
}

enum OriginKind {
  definition,
  reference,
  usage;

  String get str => switch (this) {
        OriginKind.definition => 'definition',
        OriginKind.reference => 'reference',
        OriginKind.usage => 'usage',
      };
}

enum OriginFormat {
  dotenv,
  dockerCompose,
  githubActions,
  kubernetes,
  source;

  String get str => switch (this) {
        OriginFormat.dotenv => 'dotenv',
        OriginFormat.dockerCompose => 'docker-compose',
        OriginFormat.githubActions => 'github-actions',
        OriginFormat.kubernetes => 'kubernetes',
        OriginFormat.source => 'source',
      };
}
