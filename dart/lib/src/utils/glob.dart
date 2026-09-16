/// A tiny glob-to-regex converter for matching variable names and file paths
/// against config patterns. Supports `*` (within a segment), `**`, and `?`.
library;

final Map<String, RegExp> _cache = {};

RegExp globToRegExp(String pattern) {
  final cached = _cache[pattern];
  if (cached != null) return cached;
  final sb = StringBuffer('^');
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    if (c == '*') {
      if (i + 1 < pattern.length && pattern[i + 1] == '*') {
        sb.write('.*');
        i += 2;
      } else {
        sb.write('[^/]*');
        i += 1;
      }
    } else if (c == '?') {
      sb.write('[^/]');
      i += 1;
    } else {
      if (r'.+?^${}()|[]\\'.contains(c)) sb.write('\\');
      sb.write(c);
      i += 1;
    }
  }
  sb.write(r'$');
  final re = RegExp(sb.toString());
  _cache[pattern] = re;
  return re;
}

bool matchesGlob(String pattern, String value) => globToRegExp(pattern).hasMatch(value);

bool matchesAnyGlob(List<String> patterns, String value) =>
    patterns.any((p) => matchesGlob(p, value));
