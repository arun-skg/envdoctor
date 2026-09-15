/// The basic value types envdoctor can infer from a variable's value.
enum VariableType {
  integer,
  float,
  boolean,
  url,
  json,
  string,
  unknown;

  String get str => switch (this) {
        VariableType.integer => 'integer',
        VariableType.float => 'float',
        VariableType.boolean => 'boolean',
        VariableType.url => 'url',
        VariableType.json => 'json',
        VariableType.string => 'string',
        VariableType.unknown => 'unknown',
      };
}
