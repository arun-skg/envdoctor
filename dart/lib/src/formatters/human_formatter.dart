/// Render a full audit report matching the TypeScript reference's
/// `renderReport`. Colors are intentionally omitted: the reference uses chalk,
/// which emits no escape codes when stdout is not a TTY, so the plain text
/// produced here is byte-identical to the reference in piped/CI contexts.
library;

import '../models/finding.dart';
import '../models/origin.dart';
import '../utils/paths.dart';

typedef LineRenderer = List<String> Function(Finding f, String root, bool verbose);

class _SectionSpec {
  final String heading;
  final List<String> ruleIds;
  final LineRenderer line;
  _SectionSpec(this.heading, this.ruleIds, this.line);
}

List<String> _locationLines(Finding f, String root, bool verbose) {
  if (!verbose || f.locations.isEmpty) return [];
  return f.locations.take(3).map((o) => '  · ${renderLocation(root, o)}').toList();
}

final List<_SectionSpec> _sectionSpecs = [
  _SectionSpec('Missing', ['missing', 'undefined-in-source'], (f, root, verbose) {
    final where = f.locations.isNotEmpty
        ? 'referenced in ${f.locations.map((o) => renderLocation(root, o)).join(', ')}'
        : 'referenced but never defined';
    final lines = ['  ${f.variable}  $where'];
    lines.addAll(_locationLines(f, root, verbose));
    return lines;
  }),
  _SectionSpec('Defined but unused', ['unused'], (f, root, _) {
    final where = f.locations.isNotEmpty
        ? 'defined in ${f.locations.map((o) => renderLocation(root, o)).join(', ')}'
        : '';
    return ['  ${f.variable}  $where'];
  }),
  _SectionSpec('Duplicates', ['duplicates'], (f, _, _) => ['  ${f.variable}  ${f.message}']),
  _SectionSpec('Type mismatch', ['type-mismatch'], (f, _, _) {
    final lines = ['  ${f.variable}'];
    final expected = _captureAfter(f.message, 'expected:');
    final found = _captureAfter(f.message, 'found:');
    if (expected != null) lines.add('    expected: $expected');
    if (found != null) lines.add('    found: $found');
    return lines;
  }),
  _SectionSpec('Environment differences', ['environment-diff'], (f, _, _) {
    return ['  ${f.message}'];
  }),
  _SectionSpec('Public secret leak', ['public-prefix'], (f, root, verbose) {
    final lines = ['  ${f.variable}'];
    lines.addAll(_locationLines(f, root, verbose));
    return lines;
  }),
  _SectionSpec('Weak secrets', ['weak-secret'], (f, _, _) => ['  ${f.variable}  ${f.message}']),
  _SectionSpec('Possible typos', ['typo'], (f, root, verbose) {
    final lines = ['  ${f.variable}  ${f.message}'];
    lines.addAll(_locationLines(f, root, verbose));
    return lines;
  }),
  _SectionSpec('Schema validation', ['schema-validation'], (f, root, verbose) {
    final lines = ['  ${f.variable}  ${f.message}'];
    lines.addAll(_locationLines(f, root, verbose));
    return lines;
  }),
];

String renderReport(
    List<Finding> findings, AuditSummary summary, String rootDir, bool verbose) {
  final lines = <String>[];

  const title = 'ENVIRONMENT AUDIT';
  lines.add(title);
  lines.add('─' * (title.length * 2));
  lines.add('');

  if (findings.isEmpty) {
    lines.add('  ✓ No issues found');
    lines.add('');
    lines.add(_footer(summary));
    return lines.join('\n');
  }

  for (final spec in _sectionSpecs) {
    final group = findings.where((f) => spec.ruleIds.contains(f.ruleId)).toList();
    if (group.isEmpty) continue;
    lines.add(spec.heading);
    lines.add('');
    for (final f in group) {
      lines.addAll(spec.line(f, rootDir, verbose));
    }
    lines.add('');
  }

  lines.add(_footer(summary));
  return lines.join('\n');
}

/// Render a single location as `relative/path:line`.
String renderLocation(String root, Origin origin) {
  final path = displayPath(root, origin.filePath);
  final line = origin.line;
  return line != null ? '$path:$line' : path;
}

String _footer(AuditSummary summary) {
  final errors = summary.errors > 0 ? '${summary.errors} error${_plural(summary.errors)}' : '0 errors';
  final warnings = summary.warnings > 0
      ? '${summary.warnings} warning${_plural(summary.warnings)}'
      : '0 warnings';
  return 'Summary: ${summary.filesScanned} files scanned · ${summary.variablesFound} variables · $errors · $warnings';
}

String _plural(int n) => n == 1 ? '' : 's';

/// Extract the token after a label like `expected:` / `found:` (letters only,
/// case-insensitive), mirroring the reference regex `/label\s*([a-z]+)/i`.
String? _captureAfter(String message, String label) {
  final idx = message.toLowerCase().indexOf(label.toLowerCase());
  if (idx < 0) return null;
  final rest = message.substring(idx + label.length).trimLeft();
  final sb = StringBuffer();
  for (final c in rest.codeUnits) {
    final isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
    if (!isLetter) break;
    sb.writeCharCode(c);
  }
  return sb.isEmpty ? null : sb.toString();
}
