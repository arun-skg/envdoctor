/// Scans for `process.env.NAME`, `process.env['NAME']`, and
/// `import.meta.env.NAME` usages. Comments and string literals are stripped
/// first (a state machine that understands quotes, escape sequences, template
/// literals, and `${...}` interpolation) so documented/string occurrences
/// don't create false positives.
library;

import '../models/environment_file.dart';
import '../models/environment_variable.dart';
import '../models/origin.dart';
import '../utils/paths.dart';
import 'parser.dart';

class SourceParser implements Parser {
  static final List<RegExp> patterns = [
    RegExp(r'\bprocess\.env\.([A-Za-z_$][A-Za-z0-9_$]*)'),
    RegExp(r'''\bprocess\.env\[['"]([A-Za-z_$][A-Za-z0-9_$]*)['"]\]'''),
    RegExp(r'\bimport\.meta\.env\.([A-Za-z_$][A-Za-z0-9_$]*)'),
  ];

  final Set<String> _extSet;

  SourceParser(List<String> extensions)
      : _extSet = extensions.map((e) {
          var s = e;
          while (s.startsWith('.')) {
            s = s.substring(1);
          }
          return s.toLowerCase();
        }).toSet();

  @override
  String get id => 'source';

  @override
  bool matchPath(String filePath) {
    final ext = extensionOf(filePath).toLowerCase();
    return ext.isNotEmpty && _extSet.contains(ext);
  }

  @override
  EnvironmentFile parse(String content, String filePath) {
    final stripped = stripComments(content);
    final usages = <EnvironmentVariable>[];

    for (final re in patterns) {
      for (final match in re.allMatches(stripped)) {
        final name = match.group(1)!;
        final origin = Origin(
          filePath: filePath,
          line: _lineNumberAt(stripped, match.start),
          kind: OriginKind.usage,
          format: OriginFormat.source,
        );
        usages.add(EnvironmentVariable.create(name, null, [origin]));
      }
    }

    return EnvironmentFile(
      filePath: filePath,
      format: FileFormat.source,
      usages: EnvironmentVariable.merge(usages),
    );
  }

  /// 1-based line number for a character offset in `text`.
  static int _lineNumberAt(String text, int offset) {
    final end = offset < text.length ? offset : text.length;
    var line = 1;
    for (var i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }
}

enum _Mode { code, codeTpl, sq, dq, tq }

class _Frame {
  _Mode mode;
  int tplDepth;
  bool preserve;
  _Frame(this.mode, {this.tplDepth = 0, this.preserve = false});
}

/// Replace comments and string-literal *contents* with spaces while
/// preserving line structure. Template-literal `${...}` interpolation is
/// treated as code so `process.env.X` inside it is still found.
String stripComments(String code) {
  final out = StringBuffer();
  final len = code.length;
  var i = 0;
  final stack = <_Frame>[_Frame(_Mode.code)];

  void skipLineComment() {
    while (i < len && code.codeUnitAt(i) != 0x0A) {
      out.write(' ');
      i++;
    }
  }

  void skipBlockComment() {
    out.write('  ');
    i += 2;
    while (i < len) {
      if (code.codeUnitAt(i) == 0x2A &&
          i + 1 < len &&
          code.codeUnitAt(i + 1) == 0x2F) {
        out.write('  ');
        i += 2;
        return;
      }
      out.write(code.codeUnitAt(i) == 0x0A ? '\n' : ' ');
      i++;
    }
  }

  while (i < len) {
    final c = code.codeUnitAt(i);
    final next = i + 1 < len ? code.codeUnitAt(i + 1) : null;
    final top = stack.last;
    final mode = top.mode;

    if (mode == _Mode.code || mode == _Mode.codeTpl) {
      if (c == 0x27 || c == 0x22 || c == 0x60) {
        final stringMode = switch (c) {
          0x60 => _Mode.tq,
          0x22 => _Mode.dq,
          _ => _Mode.sq,
        };
        // A string that immediately follows `[` is a computed-property key.
        final preserve = c != 0x60 && i > 0 && code.codeUnitAt(i - 1) == 0x5B;
        stack.add(_Frame(stringMode, preserve: preserve));
        out.writeCharCode(c);
        i++;
      } else if (c == 0x2F && next == 0x2F) {
        skipLineComment();
      } else if (c == 0x2F && next == 0x2A) {
        skipBlockComment();
      } else if (mode == _Mode.codeTpl) {
        if (c == 0x7B) {
          top.tplDepth++;
        } else if (c == 0x7D) {
          top.tplDepth--;
          if (top.tplDepth == 0) stack.removeLast();
        }
        out.writeCharCode(c);
        i++;
      } else {
        out.writeCharCode(c);
        i++;
      }
    } else if (mode == _Mode.tq) {
      if (c == 0x5C && i + 1 < len) {
        out.writeCharCode(c);
        out.writeCharCode(code.codeUnitAt(i + 1));
        i += 2;
      } else if (c == 0x60) {
        stack.removeLast();
        out.writeCharCode(c);
        i++;
      } else if (c == 0x24 && next == 0x7B) {
        out.write('\${');
        i += 2;
        stack.add(_Frame(_Mode.codeTpl, tplDepth: 1));
      } else {
        // Template-literal content (not in interpolation) is blanked.
        out.write(' ');
        i++;
      }
    } else {
      // sq / dq
      final quote = mode == _Mode.sq ? 0x27 : 0x22;
      final preserve = top.preserve;
      if (c == 0x5C && i + 1 < len) {
        if (preserve) {
          out.writeCharCode(c);
          out.writeCharCode(code.codeUnitAt(i + 1));
        } else {
          out.write('  ');
        }
        i += 2;
      } else if (c == quote) {
        out.writeCharCode(c);
        i++;
        stack.removeLast();
      } else if (preserve) {
        // Preserve computed-property key content verbatim.
        out.writeCharCode(c);
        i++;
      } else {
        // Regular string literal content — blank it out.
        out.write(' ');
        i++;
      }
    }
  }

  return out.toString();
}
