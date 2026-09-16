/// A comparator matching JavaScript's `String.prototype.localeCompare` for the
/// character set used in environment-variable names (`[A-Za-z0-9_]`).
///
/// The TypeScript reference sorts generated output with `localeCompare`, which
/// is a Unicode collation (punctuation < digits < letters, case-insensitive
/// with a lowercase-before-uppercase tiebreak) — not byte order.
library;

int _primary(int c) {
  if (c >= 0x30 && c <= 0x39) return 1000 + c; // ASCII digit
  if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
    return 2000 + (c | 0x20); // ASCII letter, uppercased
  }
  return c;
}

int _caseWeight(int c) =>
    (c >= 0x61 && c <= 0x7A) ? 0 : 1; // lowercase sorts before uppercase

/// Compare two strings the way JS `a.localeCompare(b)` does for env-var names.
int localeCompare(String a, String b) {
  final len = a.length < b.length ? a.length : b.length;
  // Level 1: primary weights across all positions.
  for (var i = 0; i < len; i++) {
    final cmp = _primary(a.codeUnitAt(i)).compareTo(_primary(b.codeUnitAt(i)));
    if (cmp != 0) return cmp;
  }
  final lenCmp = a.length.compareTo(b.length);
  if (lenCmp != 0) return lenCmp;

  // Level 2: case (only reached when primaries are all equal).
  for (var i = 0; i < len; i++) {
    final cmp = _caseWeight(a.codeUnitAt(i)).compareTo(_caseWeight(b.codeUnitAt(i)));
    if (cmp != 0) return cmp;
  }
  return 0;
}

void localeSort(List<String> values) {
  values.sort(localeCompare);
}
