import 'origin.dart';
import 'variable_type.dart';
import '../utils/type_infer.dart';

/// A normalized view of one environment variable across every file in the
/// project. `value` is only ever set for definitions and is never rendered in
/// CLI output or written into generated files.
class EnvironmentVariable {
  final String name;
  String? value;
  final bool isSecret;
  VariableType type;
  final List<Origin> origins;
  final List<String>? ignoreRules;

  static final RegExp _secretNameRe = RegExp(
    r'(SECRET|TOKEN|PASSWORD|PASS|API[_A-Z]*KEY|PRIVATE[_-]?KEY|CREDENTIALS)',
    caseSensitive: false,
  );

  static bool isSecretName(String name) => _secretNameRe.hasMatch(name);

  EnvironmentVariable({
    required this.name,
    this.value,
    List<Origin>? origins,
    this.ignoreRules,
    bool? isSecret,
    VariableType? type,
  })  : isSecret = isSecret ?? isSecretName(name),
        type = type ?? inferType(value),
        origins = origins ?? [];

  EnvironmentVariable.clone(EnvironmentVariable other)
      : name = other.name,
        value = other.value,
        isSecret = other.isSecret,
        type = other.type,
        origins = other.origins.map((o) => Origin.clone(o)).toList(),
        ignoreRules = other.ignoreRules == null ? null : List.of(other.ignoreRules!);

  static EnvironmentVariable create(
    String name,
    String? value,
    List<Origin> origins, {
    List<String>? ignoreRules,
  }) =>
      EnvironmentVariable(
          name: name, value: value, origins: origins, ignoreRules: ignoreRules);

  /// Merge multiple variables with the same name into one, preserving every
  /// origin and preferring the first non-empty value.
  static List<EnvironmentVariable> merge(List<EnvironmentVariable> variables) {
    final byName = <String, EnvironmentVariable>{};
    for (final v in variables) {
      final existing = byName[v.name];
      if (existing == null) {
        byName[v.name] = EnvironmentVariable.clone(v);
      } else {
        existing.origins.addAll(v.origins.map((o) => Origin.clone(o)));
        if (existing.value == null && v.value != null) {
          existing.value = v.value;
          existing.type = inferType(v.value);
        }
      }
    }
    return byName.values.toList();
  }
}
