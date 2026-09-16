/// Helpers over package:yaml that reproduce the scalar-resolution semantics
/// of the reference's `yaml` npm package (YAML 1.2 core schema): plain
/// scalars become null/bool/int/float/string; quoted scalars are always
/// strings.
library;

import 'package:yaml/yaml.dart';

import '../utils/json.dart';

final RegExp _intRe = RegExp(r'^[-+]?[0-9]+$');
final RegExp _hexIntRe = RegExp(r'^0x[0-9a-fA-F]+$');
final RegExp _octIntRe = RegExp(r'^0o[0-7]+$');
final RegExp _floatRe = RegExp(r'^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$');

/// Parse all documents; returns an empty list when the content is not
/// parseable YAML (callers still scan raw text for interpolations).
List<Object?> yamlLoadAll(String content) {
  try {
    return loadYamlDocuments(content).map((d) => yamlToPlain(d.contents)).toList();
  } catch (_) {
    return <Object?>[];
  }
}

/// Parse the first document; null when unparseable.
Object? yamlLoadFirst(String content) {
  final docs = yamlLoadAll(content);
  return docs.isNotEmpty ? docs.first : null;
}

Object? yamlToPlain(YamlNode node) => switch (node) {
      YamlScalar scalar => resolveScalar(scalar),
      YamlList list => list.nodes.map(yamlToPlain).toList(),
      YamlMap map => {
          for (final entry in map.nodes.entries)
            jsString(yamlToPlain(entry.key)): yamlToPlain(entry.value),
        },
      _ => null,
    };

Object? resolveScalar(YamlScalar scalar) {
  if (scalar.style != ScalarStyle.PLAIN) return scalar.value?.toString() ?? '';
  final s = scalar.span.text;
  if (s.isEmpty || s == '~' || s == 'null' || s == 'Null' || s == 'NULL') return null;
  if (s == 'true' || s == 'True' || s == 'TRUE') return true;
  if (s == 'false' || s == 'False' || s == 'FALSE') return false;
  if (_intRe.hasMatch(s)) {
    final v = int.tryParse(s);
    if (v != null) return v;
  }
  if (_hexIntRe.hasMatch(s)) {
    final v = int.tryParse(s.substring(2), radix: 16);
    if (v != null) return v;
  }
  if (_octIntRe.hasMatch(s)) {
    final v = int.tryParse(s.substring(2), radix: 8);
    if (v != null) return v;
  }
  if ((s.contains('.') || s.contains('e') || s.contains('E')) && _floatRe.hasMatch(s)) {
    final v = double.tryParse(s);
    if (v != null) return v;
  }
  return s;
}

/// JS `String(value)` for the scalar shapes YAML resolution produces.
String jsString(Object? value) => switch (value) {
      null => 'null',
      String s => s,
      bool b => b ? 'true' : 'false',
      int i => i.toString(),
      double d => jsNumberToString(d),
      List<Object?> list => list.map(jsString).join(','),
      Map<String, Object?> _ => '[object Object]',
      _ => value.toString(),
    };
