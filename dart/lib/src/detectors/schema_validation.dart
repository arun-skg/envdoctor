import 'dart:convert';

import '../config/config.dart';
import '../models/finding.dart';
import 'detector.dart';

/// Schema-validation: a variable value does not match its declared schema.
/// Error messages mirror the reference CLI's zod-based validator.
class SchemaValidationDetector implements Detector {
  @override
  String get id => 'schema-validation';

  @override
  String get name => 'schema-validation';

  @override
  String get description =>
      'A variable value does not match its declared schema.';

  @override
  List<Finding> detect(IndexedModel index) {
    final schema = index.model.config.schema;
    if (schema.isEmpty) return [];

    final findings = <Finding>[];

    for (final entry in sortedEntries(index.envDefinitions, defSortKey)) {
      final variableSchema = schema[entry.key];
      if (variableSchema == null) continue;

      for (final def in entry.value) {
        final error = validateValue(def.value, variableSchema);
        if (error == null) continue;
        findings.add(Finding.make(
          'schema-validation',
          Severity.error,
          entry.key,
          'does not match schema: $error',
          [def.origin],
        ));
      }
    }

    return findings;
  }

  static String? validateValue(String? value, VariableSchema schema) {
    if (value == null || value.trim().isEmpty) {
      return schema.optional == true ? null : 'value is required';
    }
    return _buildValidator(schema)?.call(value);
  }

  static String? Function(String)? _buildValidator(VariableSchema schema) {
    final enumValues = schema.enumValues;
    if (enumValues != null && enumValues.isNotEmpty) {
      final quoted = enumValues.map((v) => '"$v"').join('|');
      return (v) =>
          enumValues.contains(v) ? null : 'Invalid option: expected one of $quoted';
    }

    switch (schema.type) {
      case SchemaType.integer:
        final min = schema.min;
        final max = schema.max;
        return (v) {
          final n = jsNumber(v);
          if (n == null || n.isNaN) return 'Invalid input: expected number, received NaN';
          if (!isJsInteger(n)) return 'Invalid input: expected int, received number';
          if (min != null && n < min) {
            return 'Too small: expected number to be >=$min';
          }
          if (max != null && n > max) {
            return 'Too big: expected number to be <=$max';
          }
          return null;
        };
      case SchemaType.float:
        final min = schema.min;
        final max = schema.max;
        return (v) {
          final n = jsNumber(v);
          if (n == null || n.isNaN) return 'Invalid input: expected number, received NaN';
          if (min != null && n < min) {
            return 'Too small: expected number to be >=$min';
          }
          if (max != null && n > max) {
            return 'Too big: expected number to be <=$max';
          }
          return null;
        };
      case SchemaType.boolean:
        // z.coerce.boolean() accepts any non-empty string.
        return (_) => null;
      case SchemaType.url:
        // zod's .url() accepts anything the WHATWG URL constructor accepts.
        return (v) => isValidJsUrl(v) ? null : 'Invalid URL';
      case SchemaType.json:
        return (v) {
          try {
            jsonDecode(v);
            return null;
          } catch (_) {
            return 'must be valid JSON';
          }
        };
      case SchemaType.regex:
        final regexStr = schema.regex;
        if (regexStr == null) return null;
        final RegExp re;
        try {
          re = RegExp(regexStr);
        } catch (_) {
          return null;
        }
        return (v) => re.hasMatch(v) ? null : 'must match $regexStr';
      case SchemaType.string:
      case SchemaType.enumType:
      case null:
        return null;
    }
  }
}

/// JS `Number(value)` for the inputs envdoctor sees: null when NaN.
double? jsNumber(String v) {
  final trimmed = v.trim();
  if (trimmed.isEmpty) return 0; // JS Number('') === 0 (empty values are filtered earlier)
  // Hex / octal literals.
  final hex = RegExp(r'^[+-]?0x[0-9a-fA-F]+$');
  if (hex.hasMatch(trimmed)) {
    final neg = trimmed.startsWith('-');
    final digits = trimmed.replaceFirst(RegExp(r'^[+-]?0x'), '');
    final n = int.tryParse(digits, radix: 16);
    if (n == null) return null;
    return (neg ? -1 : 1) * n.toDouble();
  }
  if (RegExp(r'^[+-]?0o[0-7]+$').hasMatch(trimmed)) {
    final neg = trimmed.startsWith('-');
    final digits = trimmed.replaceFirst(RegExp(r'^[+-]?0o'), '');
    final n = int.tryParse(digits, radix: 8);
    if (n == null) return null;
    return (neg ? -1 : 1) * n.toDouble();
  }
  if (trimmed == 'Infinity' || trimmed == '+Infinity') return double.infinity;
  if (trimmed == '-Infinity') return double.negativeInfinity;
  // Decimal: JS accepts "12", "1.5", ".5", "5.", "1e3", and nothing else.
  if (!RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$').hasMatch(trimmed)) {
    return null; // NaN
  }
  return double.tryParse(trimmed);
}

bool isJsInteger(double n) =>
    n.isFinite && n == n.truncateToDouble() && n.abs() <= 9007199254740991;

/// WHATWG URL validation approximation: a scheme followed by a non-empty
/// hierarchical part, no whitespace.
bool isValidJsUrl(String v) {
  final match = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):(.*)$').firstMatch(v.trim());
  if (match == null) return false;
  final rest = match.group(2)!;
  if (rest.isEmpty) return false;
  if (RegExp(r'\s').hasMatch(v.trim())) return false;
  return true;
}
