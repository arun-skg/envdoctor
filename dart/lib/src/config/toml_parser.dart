/// A small TOML parser covering the subset of TOML envdoctor configs use:
/// tables (`[section]`, `[a.b]`), key/value pairs, strings (basic + literal),
/// integers, floats, booleans, arrays (including nested), and inline tables.
library;

class TomlParseException implements Exception {
  final String message;
  TomlParseException(this.message);
  @override
  String toString() => message;
}

/// Parse TOML text into nested `Map<String, Object?>` with plain Dart values.
Map<String, Object?> parseToml(String content) {
  final root = <String, Object?>{};
  var current = root;
  final lines = content.split('\n');
  var i = 0;
  while (i < lines.length) {
    var line = _stripComment(lines[i]);
    final trimmed = line.trim();
    i++;
    if (trimmed.isEmpty) continue;

    if (trimmed.startsWith('[') && trimmed.endsWith(']') && !trimmed.startsWith('[[')) {
      // Table header.
      final path = trimmed.substring(1, trimmed.length - 1).trim();
      current = _resolveTable(root, path);
      continue;
    }
    if (trimmed.startsWith('[[')) {
      throw TomlParseException('array-of-tables are not supported in envdoctor configs');
    }

    final eq = _findKeySeparator(trimmed);
    if (eq < 0) throw TomlParseException('expected key = value, got: $trimmed');
    final key = _unquoteKey(trimmed.substring(0, eq).trim());
    var valueText = trimmed.substring(eq + 1).trim();
    if (valueText.startsWith('[') && !_balancedBrackets(valueText)) {
      // Multi-line array: keep consuming lines until brackets balance.
      final sb = StringBuffer(valueText);
      while (i < lines.length && !_balancedBrackets(sb.toString())) {
        sb.write('\n');
        sb.write(_stripComment(lines[i]));
        i++;
      }
      valueText = sb.toString().trim();
    }
    _parseKeyValue(current, key, valueText);
  }
  return root;
}

void _parseKeyValue(Map<String, Object?> table, String key, String valueText) {
  table[key] = _parseValue(valueText.trim());
}

Map<String, Object?> _resolveTable(Map<String, Object?> root, String path) {
  var current = root;
  for (final part in path.split('.')) {
    final key = _unquoteKey(part.trim());
    final existing = current[key];
    if (existing is Map<String, Object?>) {
      current = existing;
    } else {
      final next = <String, Object?>{};
      current[key] = next;
      current = next;
    }
  }
  return current;
}

String _unquoteKey(String key) {
  if (key.length >= 2 && key.startsWith('"') && key.endsWith('"')) {
    return _parseBasicString(key);
  }
  if (key.length >= 2 && key.startsWith("'") && key.endsWith("'")) {
    return key.substring(1, key.length - 1);
  }
  return key;
}

/// Find the `=` separating key and value, ignoring `=` inside quotes.
int _findKeySeparator(String line) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inSingle) {
      if (c == "'") inSingle = false;
    } else if (inDouble) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inDouble = false;
      }
    } else if (c == "'") {
      inSingle = true;
    } else if (c == '"') {
      inDouble = true;
    } else if (c == '=') {
      return i;
    }
  }
  return -1;
}

String _stripComment(String line) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inSingle) {
      if (c == "'") inSingle = false;
    } else if (inDouble) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inDouble = false;
      }
    } else if (c == "'") {
      inSingle = true;
    } else if (c == '"') {
      inDouble = true;
    } else if (c == '#') {
      return line.substring(0, i);
    }
  }
  return line;
}

bool _balancedBrackets(String s) {
  var depth = 0;
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inSingle) {
      if (c == "'") inSingle = false;
    } else if (inDouble) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inDouble = false;
      }
    } else if (c == "'") {
      inSingle = true;
    } else if (c == '"') {
      inDouble = true;
    } else if (c == '[') {
      depth++;
    } else if (c == ']') {
      depth--;
    }
  }
  return depth <= 0;
}

Object? _parseValue(String text) {
  if (text.startsWith('[')) {
    return _parseArray(text);
  }
  if (text.startsWith('{')) {
    return _parseInlineTable(text);
  }
  if (text.startsWith('"')) {
    return _parseBasicString(text);
  }
  if (text.startsWith("'")) {
    return text.substring(1, text.length - 1);
  }
  if (text == 'true') return true;
  if (text == 'false') return false;
  final intValue = int.tryParse(text.replaceAll('_', ''));
  if (intValue != null &&
      RegExp(r'^[-+]?[0-9_]+$').hasMatch(text)) {
    return intValue;
  }
  final floatValue = double.tryParse(text.replaceAll('_', ''));
  if (floatValue != null &&
      RegExp(r'^[-+]?[0-9][0-9_]*(\.[0-9_]+)?([eE][-+]?[0-9]+)?$').hasMatch(text)) {
    return floatValue;
  }
  throw TomlParseException('unsupported TOML value: $text');
}

String _parseBasicString(String text) {
  // text includes surrounding quotes.
  final inner = text.substring(1, text.length - 1);
  final sb = StringBuffer();
  var i = 0;
  while (i < inner.length) {
    final c = inner[i];
    if (c == r'\') {
      if (i + 1 >= inner.length) break;
      final next = inner[i + 1];
      switch (next) {
        case 'n':
          sb.write('\n');
        case 't':
          sb.write('\t');
        case 'r':
          sb.write('\r');
        case 'b':
          sb.write('\b');
        case 'f':
          sb.write('\f');
        case 'u':
          sb.writeCharCode(
              int.parse(inner.substring(i + 2, i + 6), radix: 16));
          i += 4;
        case 'U':
          sb.writeCharCode(
              int.parse(inner.substring(i + 2, i + 10), radix: 16));
          i += 8;
        case '"':
          sb.write('"');
        case r'\':
          sb.write(r'\');
        default:
          sb.write(next);
      }
      i += 2;
    } else {
      sb.write(c);
      i++;
    }
  }
  return sb.toString();
}

List<Object?> _parseArray(String text) {
  // text starts with '[' and ends with ']'.
  var inner = text.substring(1).trim();
  if (inner.endsWith(']')) inner = inner.substring(0, inner.length - 1);
  final items = <Object?>[];
  var depth = 0;
  var inSingle = false;
  var inDouble = false;
  var start = 0;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (inSingle) {
      if (c == "'") inSingle = false;
    } else if (inDouble) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inDouble = false;
      }
    } else if (c == "'") {
      inSingle = true;
    } else if (c == '"') {
      inDouble = true;
    } else if (c == '[' || c == '{') {
      depth++;
    } else if (c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      final item = inner.substring(start, i).trim();
      if (item.isNotEmpty) items.add(_parseValue(item));
      start = i + 1;
    }
  }
  final last = inner.substring(start).trim();
  if (last.isNotEmpty) items.add(_parseValue(last));
  return items;
}

Map<String, Object?> _parseInlineTable(String text) {
  // text starts with '{' and ends with '}'.
  var inner = text.substring(1).trim();
  if (inner.endsWith('}')) inner = inner.substring(0, inner.length - 1);
  final result = <String, Object?>{};
  var depth = 0;
  var inSingle = false;
  var inDouble = false;
  var start = 0;
  for (var i = 0; i < inner.length; i++) {
    final c = inner[i];
    if (inSingle) {
      if (c == "'") inSingle = false;
    } else if (inDouble) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inDouble = false;
      }
    } else if (c == "'") {
      inSingle = true;
    } else if (c == '"') {
      inDouble = true;
    } else if (c == '[' || c == '{') {
      depth++;
    } else if (c == ']' || c == '}') {
      depth--;
    } else if (c == ',' && depth == 0) {
      _parseInlineEntry(result, inner.substring(start, i).trim());
      start = i + 1;
    }
  }
  _parseInlineEntry(result, inner.substring(start).trim());
  return result;
}

void _parseInlineEntry(Map<String, Object?> table, String entry) {
  if (entry.isEmpty) return;
  final eq = _findKeySeparator(entry);
  if (eq < 0) throw TomlParseException('expected key = value in inline table, got: $entry');
  final key = _unquoteKey(entry.substring(0, eq).trim());
  table[key] = _parseValue(entry.substring(eq + 1).trim());
}
