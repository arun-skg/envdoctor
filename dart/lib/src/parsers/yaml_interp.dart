/// Helpers for scanning shell-style variable interpolation in YAML-based
/// formats (docker-compose, GitHub Actions). Shared because both formats use
/// `$VAR` / `${VAR}` and need 1-based line numbers for origins.
library;

class Interpolation {
  final String name;
  final int line;
  Interpolation(this.name, this.line);
}

final RegExp _interpRe = RegExp(
  r'\$(?:\{([A-Za-z_][A-Za-z0-9_]*)(?:\s*[:-?+][^}]*)?\}|([A-Za-z_][A-Za-z0-9_]*))',
);

/// Compute the 1-based line number of a character offset in `content`.
int lineForOffset(String content, int offset) {
  final end = offset < content.length ? offset : content.length;
  var line = 1;
  for (var i = 0; i < end; i++) {
    if (content.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// Scan `content` for `$VAR` and `${VAR}` interpolations, honoring the `$$`
/// escape. `{...}` modifiers (e.g. `${VAR:-x}`) are stripped — only the name
/// is kept.
List<Interpolation> scanInterpolations(String content) {
  // Protect escaped `$$` (same length, so offsets stay valid) so the second
  // `$` is never mistaken for a real interpolation.
  final protected = content.replaceAll('\$\$', '  ');
  final results = <Interpolation>[];
  for (final match in _interpRe.allMatches(protected)) {
    final name = match.group(1) ?? match.group(2);
    if (name == null) continue;
    results.add(Interpolation(name, lineForOffset(content, match.start)));
  }
  return results;
}
