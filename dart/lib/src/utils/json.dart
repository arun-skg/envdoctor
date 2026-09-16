/// A minimal JSON writer producing the exact byte shape shared by
/// `JSON.stringify(x, null, 2)`: two-space indentation, `": "` key separator,
/// `{}`/`[]` for empty containers, and control-character escaping with
/// lowercase hex.
library;

/// An insertion-ordered JSON object.
class JsonObject {
  final List<(String, Object?)> entries = [];

  void add(String key, Object? value) => entries.add((key, value));
}

String jsonPretty(Object? value) {
  final sb = StringBuffer();
  _write(sb, value, 0, true);
  return sb.toString();
}

String jsonCompact(Object? value) {
  final sb = StringBuffer();
  _write(sb, value, 0, false);
  return sb.toString();
}

void _write(StringBuffer sb, Object? value, int depth, bool pretty) {
  switch (value) {
    case null:
      sb.write('null');
    case bool b:
      sb.write(b ? 'true' : 'false');
    case String s:
      _writeString(sb, s);
    case int i:
      sb.write(i);
    case double d:
      sb.write(jsNumberToString(d));
    case JsonObject obj:
      _writeObject(sb, obj.entries, depth, pretty);
    case Map<String, Object?> map:
      _writeObject(sb, map.entries.map((e) => (e.key, e.value)).toList(), depth, pretty);
    case Iterable list:
      _writeArray(sb, list.toList(), depth, pretty);
    default:
      throw ArgumentError('Unsupported JSON value type: ${value.runtimeType}');
  }
}

void _writeObject(StringBuffer sb, List<(String, Object?)> entries, int depth, bool pretty) {
  if (entries.isEmpty) {
    sb.write('{}');
    return;
  }
  sb.write('{');
  for (var i = 0; i < entries.length; i++) {
    if (pretty) {
      sb.write('\n');
      _indent(sb, depth + 1);
    }
    _writeString(sb, entries[i].$1);
    sb.write(pretty ? ': ' : ':');
    _write(sb, entries[i].$2, depth + 1, pretty);
    if (i < entries.length - 1) sb.write(',');
  }
  if (pretty) {
    sb.write('\n');
    _indent(sb, depth);
  }
  sb.write('}');
}

void _writeArray(StringBuffer sb, List<Object?> items, int depth, bool pretty) {
  if (items.isEmpty) {
    sb.write('[]');
    return;
  }
  sb.write('[');
  for (var i = 0; i < items.length; i++) {
    if (pretty) {
      sb.write('\n');
      _indent(sb, depth + 1);
    }
    _write(sb, items[i], depth + 1, pretty);
    if (i < items.length - 1) sb.write(',');
  }
  if (pretty) {
    sb.write('\n');
    _indent(sb, depth);
  }
  sb.write(']');
}

void _indent(StringBuffer sb, int depth) {
  for (var i = 0; i < depth; i++) {
    sb.write('  ');
  }
}

void _writeString(StringBuffer sb, String s) {
  sb.write('"');
  for (final c in s.codeUnits) {
    switch (c) {
      case 0x22:
        sb.write(r'\"');
      case 0x5C:
        sb.write(r'\\');
      case 0x08:
        sb.write(r'\b');
      case 0x0C:
        sb.write(r'\f');
      case 0x0A:
        sb.write(r'\n');
      case 0x0D:
        sb.write(r'\r');
      case 0x09:
        sb.write(r'\t');
      default:
        if (c < 0x20) {
          sb.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          sb.writeCharCode(c);
        }
    }
  }
  sb.write('"');
}

/// JS number-to-string: shortest round-trip, matching
/// `Number.prototype.toString` for the values envdoctor emits.
String jsNumberToString(double d) {
  if (d == d.truncateToDouble() && d.abs() < 1e21) {
    return d.truncate().toString();
  }
  var s = d.toString();
  // Dart uses "1e-7" style too, but emits "1e+21"? Normalize exponent form.
  final eIdx = s.indexOf('e');
  if (eIdx >= 0) {
    var mantissa = s.substring(0, eIdx);
    var exp = s.substring(eIdx + 1);
    var neg = false;
    if (exp.startsWith('-')) {
      neg = true;
      exp = exp.substring(1);
    } else if (exp.startsWith('+')) {
      exp = exp.substring(1);
    }
    exp = exp.replaceFirst(RegExp('^0+'), '');
    if (exp.isEmpty) exp = '0';
    s = '${mantissa}e${neg ? '-' : '+'}$exp';
  }
  return s;
}
