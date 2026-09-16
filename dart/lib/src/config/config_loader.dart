/// Load and validate the config for a project root. Falls back to defaults
/// when no config exists. Throws [ConfigError] when a config file is present
/// but invalid.
library;

import 'dart:convert';
import 'dart:io';

import '../utils/paths.dart';
import 'config.dart';
import 'toml_parser.dart';

class ConfigError implements Exception {
  final String message;
  ConfigError(this.message);
  @override
  String toString() => message;
}

class ConfigLoader {
  static const List<String> configBasenames = [
    'envdoctor.config.toml',
    'envdoctor.config.json',
  ];

  /// Load the config for a project root, falling back to defaults.
  static EnvdoctorConfig loadConfig(String rootDir) {
    final configPath = findConfigFile(rootDir);
    final pkgConfig = readPackageJsonConfig(rootDir);

    if (configPath == null && pkgConfig == null) return EnvdoctorConfig();

    Map<String, Object?> raw;
    if (configPath != null) {
      final String content;
      try {
        content = File(configPath).readAsStringSync();
      } catch (e) {
        throw ConfigError(
            'Could not load config $configPath: $e. Use envdoctor.config.toml (or package.json#envdoctor).');
      }

      try {
        if (extensionOf(configPath) == 'toml') {
          raw = parseToml(content);
        } else {
          final decoded = jsonDecode(content);
          if (decoded is! Map<String, Object?>) {
            throw const FormatException('top-level value must be an object');
          }
          raw = decoded;
        }
      } on ConfigError {
        rethrow;
      } catch (e) {
        throw ConfigError('Invalid envdoctor config: $e');
      }
    } else {
      raw = pkgConfig!;
    }

    try {
      return mapConfig(raw);
    } on ConfigError {
      rethrow;
    } catch (e) {
      throw ConfigError('Invalid envdoctor config: $e');
    }
  }

  /// Like [loadConfig] but silently falls back to defaults on error,
  /// matching the reference pipeline's `unwrap_or_default()`.
  static EnvdoctorConfig loadConfigOrDefault(String rootDir) {
    try {
      return loadConfig(rootDir);
    } on ConfigError {
      return EnvdoctorConfig();
    }
  }

  static String? findConfigFile(String rootDir) {
    for (final basename_ in configBasenames) {
      final candidate = joinPath(rootDir, basename_);
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  static Map<String, Object?>? readPackageJsonConfig(String rootDir) {
    try {
      final content = File(joinPath(rootDir, 'package.json')).readAsStringSync();
      final doc = jsonDecode(content);
      if (doc is Map<String, Object?> && doc['envdoctor'] is Map<String, Object?>) {
        return doc['envdoctor'] as Map<String, Object?>;
      }
    } catch (_) {
      // no package.json or unreadable — treat as absent
    }
    return null;
  }

  static EnvdoctorConfig mapConfig(Map<String, Object?> raw) {
    final config = EnvdoctorConfig();
    raw.forEach((key, value) {
      switch (key) {
        case 'envFilePatterns':
          config.envFilePatterns = _asStringList(value);
        case 'composeFilePatterns':
          config.composeFilePatterns = _asStringList(value);
        case 'actionsFilePatterns':
          config.actionsFilePatterns = _asStringList(value);
        case 'k8sFilePatterns':
          config.k8sFilePatterns = _asStringList(value);
        case 'sourceExtensions':
          config.sourceExtensions = _asStringList(value);
        case 'ignoreVariables':
          config.ignoreVariables = _asStringList(value);
        case 'ignoreFiles':
          config.ignoreFiles = _asStringList(value);
        case 'environments':
          config.environments = _asMap(value).map(
                (k, v) => MapEntry(k, _asStringList(v)),
              );
        case 'strict':
          config.strict = _asBool(value);
        case 'rules':
          config.rules = _asMap(value).map(
                (k, v) => MapEntry(k, _parseRuleSeverity(v)),
              );
        case 'schema':
          config.schema = _asMap(value).map(
                (k, v) => MapEntry(k, _parseVariableSchema(v)),
              );
        default:
          // Unknown keys are ignored, matching the reference's default behavior.
          break;
      }
    });
    return config;
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const FormatException('expected a table/object');
  }

  static List<String> _asStringList(Object? value) {
    if (value is! List) {
      throw const FormatException('expected an array of strings');
    }
    return value
        .map((v) => v is String ? v : throw const FormatException('expected a string'))
        .toList();
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    throw const FormatException('expected a boolean');
  }

  static RuleSeverity _parseRuleSeverity(Object? value) => switch (value) {
        'error' => RuleSeverity.error,
        'warning' => RuleSeverity.warning,
        'off' => RuleSeverity.off,
        _ => throw const FormatException('expected "error", "warning", or "off"'),
      };

  static VariableSchema _parseVariableSchema(Object? value) {
    final map = _asMap(value);
    final schema = VariableSchema();
    map.forEach((key, v) {
      switch (key) {
        case 'type':
          schema.type = switch (v) {
            'string' => SchemaType.string,
            'integer' => SchemaType.integer,
            'float' => SchemaType.float,
            'boolean' => SchemaType.boolean,
            'url' => SchemaType.url,
            'json' => SchemaType.json,
            'enum' => SchemaType.enumType,
            'regex' => SchemaType.regex,
            _ => throw const FormatException('unknown schema type'),
          };
        case 'optional':
          schema.optional = _asBool(v);
        case 'enum':
        case 'enumValues':
          schema.enumValues = _asStringList(v);
        case 'regex':
          schema.regex = v is String ? v : throw const FormatException('expected a string');
        case 'min':
          schema.min = v is num ? v.toInt() : throw const FormatException('expected an integer');
        case 'max':
          schema.max = v is num ? v.toInt() : throw const FormatException('expected an integer');
      }
    });
    return schema;
  }
}
