/// envdoctor configuration model. envdoctor is configured through
/// `envdoctor.config.toml|json` or a `envdoctor` key in package.json. The
/// config is optional — defaults are sensible for most projects.
library;

enum RuleSeverity { error, warning, off }

enum SchemaType { string, integer, float, boolean, url, json, enumType, regex }

extension SchemaTypeStr on SchemaType {
  String get str => switch (this) {
        SchemaType.string => 'string',
        SchemaType.integer => 'integer',
        SchemaType.float => 'float',
        SchemaType.boolean => 'boolean',
        SchemaType.url => 'url',
        SchemaType.json => 'json',
        SchemaType.enumType => 'enum',
        SchemaType.regex => 'regex',
      };
}

class VariableSchema {
  SchemaType? type;
  bool? optional;
  List<String>? enumValues;
  String? regex;
  int? min;
  int? max;

  VariableSchema({
    this.type,
    this.optional,
    this.enumValues,
    this.regex,
    this.min,
    this.max,
  });

  VariableSchema.clone(VariableSchema other)
      : type = other.type,
        optional = other.optional,
        enumValues = other.enumValues == null ? null : List.of(other.enumValues!),
        regex = other.regex,
        min = other.min,
        max = other.max;
}

class EnvdoctorConfig {
  List<String> envFilePatterns = ['.env', '.env.*'];
  List<String> composeFilePatterns = ['**/docker-compose*.y*ml', '**/compose*.y*ml'];
  List<String> actionsFilePatterns = ['.github/workflows/**/*.y*ml'];
  List<String> k8sFilePatterns = [
    '**/*.{deployment,service,statefulset,daemonset,cronjob,job,configmap,secret,ingress,pvc}.y*ml',
    '**/k8s/**/*.y*ml',
    '**/kubernetes/**/*.y*ml',
    '**/manifests/**/*.y*ml',
    '**/deploy/**/*.y*ml',
  ];
  List<String> sourceExtensions = ['ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs'];
  List<String> ignoreVariables = [];
  List<String> ignoreFiles = [];
  Map<String, List<String>>? environments;
  bool strict = false;
  Map<String, RuleSeverity> rules = {};
  Map<String, VariableSchema> schema = {};

  EnvdoctorConfig();

  EnvdoctorConfig.clone(EnvdoctorConfig other)
      : envFilePatterns = List.of(other.envFilePatterns),
        composeFilePatterns = List.of(other.composeFilePatterns),
        actionsFilePatterns = List.of(other.actionsFilePatterns),
        k8sFilePatterns = List.of(other.k8sFilePatterns),
        sourceExtensions = List.of(other.sourceExtensions),
        ignoreVariables = List.of(other.ignoreVariables),
        ignoreFiles = List.of(other.ignoreFiles),
        environments = other.environments?.map((k, v) => MapEntry(k, List.of(v))),
        strict = other.strict,
        rules = Map.of(other.rules),
        schema = other.schema.map((k, v) => MapEntry(k, VariableSchema.clone(v)));
}
