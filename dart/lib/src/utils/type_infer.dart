/// Infer the basic type of a variable value. Ordering matters: a value like
/// "1" is an integer, "1.5" is a float, "true" is a boolean, and a URL wins
/// over generic string. Anything unparseable or empty is "string" or "unknown".
library;

import 'dart:convert';

import '../models/variable_type.dart';

final RegExp _integerRe = RegExp(r'^-?[0-9]+$');
final RegExp _floatRe = RegExp(r'^-?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?$');
final RegExp _booleanRe = RegExp(r'^(true|false|TRUE|FALSE)$');
final RegExp _urlRe = RegExp(r'^https?://\S+$', caseSensitive: false);

VariableType inferType(String? value) {
  if (value == null) return VariableType.unknown;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return VariableType.unknown;
  if (_integerRe.hasMatch(trimmed)) return VariableType.integer;
  if (_floatRe.hasMatch(trimmed)) return VariableType.float;
  if (_booleanRe.hasMatch(trimmed)) return VariableType.boolean;
  if (_urlRe.hasMatch(trimmed)) return VariableType.url;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      jsonDecode(trimmed);
      return VariableType.json;
    } catch (_) {
      // fall through to string
    }
  }
  return VariableType.string;
}
