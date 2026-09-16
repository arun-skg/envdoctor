/// Parser for dotenv-style files (`.env`, `.env.local`, `.env.production`, ...).
///
/// Hand-rolled tokenizer: the audit needs every occurrence of a key (to detect
/// duplicates and to attribute origins with line numbers), while `dotenv`
/// silently keeps only the last value for a repeated key.
library;

import '../models/environment_file.dart';
import '../models/environment_variable.dart';
import '../models/origin.dart';
import '../utils/paths.dart';
import 'parser.dart';

class EnvEntry {
  final String key;
  final String value;
  final int line;
  List<String>? ignoreRules;

  EnvEntry(this.key, this.value, this.line);
}

class IgnoreDirective {
  final int line;
  final List<String> rules;
  IgnoreDirective(this.line, this.rules);
}

class EnvParser implements Parser {
  static final RegExp _basenameRe = RegExp(r'^\.env(\..+)?$');
  static final RegExp _ignoreDirectiveRe = RegExp(
    r'^#\s*envdoctor:ignore\s+([a-z0-9_,\-\s]+)\s*$',
    caseSensitive: false,
  );

  @override
  String get id => 'dotenv';

  @override
  bool matchPath(String filePath) => _basenameRe.hasMatch(basename(filePath));

  @override
  EnvironmentFile parse(String content, String filePath) {
    final environment = environmentLabelForDotenv(filePath);
    final entries = parseDotenv(content);
    applyIgnoreDirectives(entries, parseIgnoreDirectives(content));

    final variables = <EnvironmentVariable>[];
    for (final entry in entries) {
      final origin = Origin.newDefinition(filePath, entry.line, environment);
      variables.add(EnvironmentVariable.create(entry.key, entry.value, [origin],
          ignoreRules: entry.ignoreRules));
    }

    return EnvironmentFile(
      filePath: filePath,
      format: FileFormat.dotenv,
      environment: environment,
      variables: variables,
    );
  }

  /// The environment label derived from a dotenv filename.
  static String environmentLabelForDotenv(String filePath) {
    final base = basename(filePath);
    if (base == '.env') return 'development';
    if (base == '.env.example') return 'example';
    var suffix = base.startsWith('.env.')
        ? base.substring('.env.'.length)
        : base.startsWith('.env')
            ? base.substring('.env'.length)
            : '';
    if (suffix.isEmpty) return 'development';
    // `.env.development.local` → development, `.env.test` → test
    if (suffix.endsWith('.local')) {
      suffix = suffix.substring(0, suffix.length - '.local'.length);
    }
    suffix = suffix.replaceAll(RegExp(r'\.$'), '');
    return suffix.isEmpty ? 'development' : suffix;
  }

  static bool _isKeyChar(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x5F ||
      c == 0x2E ||
      c == 0x2D; // _ . -

  static bool _isWhitespace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0B || c == 0x0C || c == 0x0D;

  /// Parse dotenv content into key/value/line entries. Handles `export `
  /// prefixes, blank lines, full-line comments, inline comments after
  /// unquoted values (respecting `\#` escapes), single/double/backtick
  /// quoting including multiline quoted values, and the common escape
  /// sequences in double-quoted values. Lines without an `=` are ignored.
  static List<EnvEntry> parseDotenv(String content) {
    final entries = <EnvEntry>[];
    final len = content.length;
    var i = 0;
    var line = 1;

    while (i < len) {
      // Skip whitespace and blank lines.
      while (i < len && _isWhitespace(content.codeUnitAt(i))) {
        if (content.codeUnitAt(i) == 0x0A) line++;
        i++;
      }
      if (i >= len) break;

      // Full-line comment.
      if (content.codeUnitAt(i) == 0x23) {
        while (i < len && content.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }

      // Optional `export` prefix, allowing spaces and tabs between the
      // prefix and the variable name (`/export[ \t]+/`).
      if (i + 6 <= len && content.startsWith('export', i)) {
        var j = i + 6;
        while (j < len &&
            (content.codeUnitAt(j) == 0x20 || content.codeUnitAt(j) == 0x09)) {
          j++;
        }
        if (j > i + 6) i = j;
      }

      final startLine = line;

      // Read the key.
      final keyStart = i;
      while (i < len && _isKeyChar(content.codeUnitAt(i))) {
        i++;
      }
      if (i == keyStart) {
        // No key, skip to end of line.
        while (i < len && content.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      final key = content.substring(keyStart, i);

      // Skip whitespace before `=`.
      while (i < len &&
          content.codeUnitAt(i) != 0x3D &&
          content.codeUnitAt(i) != 0x0A &&
          _isWhitespace(content.codeUnitAt(i))) {
        i++;
      }
      if (i >= len || content.codeUnitAt(i) != 0x3D) {
        // Malformed line (no `=`); ignore it like dotenv does.
        while (i < len && content.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      i++; // consume `=`

      // Skip whitespace before the value.
      while (i < len &&
          content.codeUnitAt(i) != 0x0A &&
          _isWhitespace(content.codeUnitAt(i))) {
        i++;
      }

      late String value;
      if (i < len) {
        final c = content.codeUnitAt(i);
        if (c == 0x22 || c == 0x27 || c == 0x60) {
          // Quoted value.
          final quote = c;
          i++;
          final raw = StringBuffer();
          while (i < len) {
            final ch = content.codeUnitAt(i);
            if (ch == quote) {
              i++;
              break;
            }
            if (ch == 0x5C) {
              if (i + 1 < len) {
                final next = content.codeUnitAt(i + 1);
                if (quote == 0x22 && next == 0x6E) {
                  // n
                  raw.write('\n');
                  i += 2;
                  continue;
                }
                if (quote == 0x22 && next == 0x74) {
                  // t
                  raw.write('\t');
                  i += 2;
                  continue;
                }
                if (quote == 0x22 && next == 0x72) {
                  // r
                  raw.write('\r');
                  i += 2;
                  continue;
                }
                if (next == 0x22 || next == 0x27 || next == 0x60 || next == 0x5C) {
                  raw.writeCharCode(next);
                  i += 2;
                  continue;
                }
              }
              raw.writeCharCode(ch);
              i++;
              continue;
            }
            raw.writeCharCode(ch);
            if (ch == 0x0A) line++;
            i++;
          }
          value = raw.toString();
        } else {
          // Unquoted value: ends at newline or an unescaped `#`.
          final raw = StringBuffer();
          while (i < len && content.codeUnitAt(i) != 0x0A) {
            final ch = content.codeUnitAt(i);
            if (ch == 0x5C && i + 1 < len && content.codeUnitAt(i + 1) == 0x23) {
              raw.write('#');
              i += 2;
              continue;
            }
            if (ch == 0x23) break;
            raw.writeCharCode(ch);
            i++;
          }
          value = raw.toString().trimRight();
        }
      } else {
        value = '';
      }

      entries.add(EnvEntry(key, value, startLine));
    }

    return entries;
  }

  /// Parse inline ignore directives placed on the line before a variable
  /// definition: `# envdoctor:ignore unused, weak-secret`.
  static List<IgnoreDirective> parseIgnoreDirectives(String content) {
    final directives = <IgnoreDirective>[];
    final lines = content.split('\n');
    for (var idx = 0; idx < lines.length; idx++) {
      final match = _ignoreDirectiveRe.firstMatch(lines[idx]);
      if (match == null) continue;
      final rules = match
          .group(1)!
          .split(RegExp(r'[,\s]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (rules.isNotEmpty) directives.add(IgnoreDirective(idx + 1, rules));
    }
    return directives;
  }

  /// Attach pending ignore directives to the first entry that appears after them.
  static void applyIgnoreDirectives(
      List<EnvEntry> entries, List<IgnoreDirective> directives) {
    final entryByLine = <int, EnvEntry>{};
    for (final e in entries) {
      entryByLine[e.line] = e;
    }

    final pending = <String>[];
    var maxLine = 1;
    for (final e in entries) {
      if (e.line > maxLine) maxLine = e.line;
    }
    for (final d in directives) {
      if (d.line > maxLine) maxLine = d.line;
    }

    for (var line = 1; line <= maxLine; line++) {
      IgnoreDirective? directive;
      for (final d in directives) {
        if (d.line == line) {
          directive = d;
          break;
        }
      }
      if (directive != null) pending.addAll(directive.rules);
      final entry = entryByLine[line];
      if (entry != null && pending.isNotEmpty) {
        entry.ignoreRules = [...(entry.ignoreRules ?? []), ...pending];
        pending.clear();
      }
    }
  }
}
