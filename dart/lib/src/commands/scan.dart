/// `envdoctor scan` — discover, parse, audit, and report.
library;

import 'dart:convert';
import 'dart:io';

import '../core/audit.dart';
import '../core/discover.dart';
import '../core/pipeline.dart';
import '../formatters/human_formatter.dart';
import '../formatters/sarif_formatter.dart';
import '../formatters/scan_json_formatter.dart';
import '../models/finding.dart';
import '../utils/json.dart';
import '../utils/paths.dart';
import 'shared.dart';

enum OutputFormat { human, json, sarif }

class ScanOptions {
  final String rootDir;
  final bool strict;
  final OutputFormat format;
  final bool verbose;
  final List<String> only;
  final String? baseline;
  final String? writeBaseline;
  final bool staged;
  final String? since;

  ScanOptions({
    required this.rootDir,
    this.strict = false,
    this.format = OutputFormat.human,
    this.verbose = false,
    this.only = const [],
    this.baseline,
    this.writeBaseline,
    this.staged = false,
    this.since,
  });
}

int runScan(ScanOptions opts) {
  final knownRules = allDetectors().map((d) => d.id).toList();
  final known = knownRules.toSet();
  for (final rule in opts.only) {
    if (!known.contains(rule)) {
      err('warning Unknown detector "$rule" (known: ${knownRules.join(', ')})\n');
    }
  }

  // Determine a git-changed file filter for --staged / --since.
  final bool filterActive = opts.staged || opts.since != null;
  if (filterActive &&
      hasNoGitChanges(opts.rootDir, staged: opts.staged ? true : null, since: opts.since)) {
    out('✓ No changed env-related files to scan\n');
    return 0;
  }

  final Set<String>? changed = opts.staged
      ? stagedFiles(opts.rootDir).toSet()
      : opts.since != null
          ? changedFilesSince(opts.rootDir, opts.since!).toSet()
          : null;

  final context = loadProjectFiltered(opts.rootDir, changed);
  final audit = runAudit(
    context.model,
    AuditOptions(strict: opts.strict, only: opts.only, rules: context.config.rules),
  );

  reportParseErrors(context.model, opts.rootDir);

  var findings = audit.findings;
  var summary = audit.summary;
  var exitCode = audit.exitCode;

  if (opts.baseline != null) {
    (findings, summary, exitCode) = _applyBaseline(
        findings, summary, opts.baseline!, opts.rootDir, opts.strict);
  }

  if (opts.writeBaseline != null) {
    _writeBaseline(findings, opts.writeBaseline!, opts.rootDir);
  }

  switch (opts.format) {
    case OutputFormat.json:
      out('${renderScanJson(opts.rootDir, findings, summary, exitCode)}\n');
    case OutputFormat.sarif:
      out('${renderSarif(findings, opts.rootDir)}\n');
    case OutputFormat.human:
      out('${renderReport(findings, summary, opts.rootDir, opts.verbose)}\n');
  }

  return exitCode;
}

class _BaselineEntry {
  final String ruleId;
  final String variable;
  final List<String> files;
  _BaselineEntry(this.ruleId, this.variable, this.files);
}

_BaselineEntry _fingerprint(Finding finding, String rootDir) {
  final files = finding.locations
      .map((o) => displayPath(rootDir, o.filePath))
      .toSet()
      .toList();
  files.sort();
  return _BaselineEntry(finding.ruleId, finding.variable, files);
}

bool _entryMatches(_BaselineEntry a, _BaselineEntry b) {
  if (a.ruleId != b.ruleId || a.variable != b.variable) return false;
  if (a.files.length != b.files.length) return false;
  for (var i = 0; i < a.files.length; i++) {
    if (a.files[i] != b.files[i]) return false;
  }
  return true;
}

(List<Finding>, AuditSummary, int) _applyBaseline(
  List<Finding> findings,
  AuditSummary summary,
  String baselinePath,
  String rootDir,
  bool strict,
) {
  final fullPath = _resolvePath(rootDir, baselinePath);
  List<_BaselineEntry> baselineEntries;
  try {
    final raw = File(fullPath).readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) throw const FormatException('bad shape');
    if (decoded['version'] is! int) throw const FormatException('bad version');
    final findingsEl = decoded['findings'];
    if (findingsEl is! List) throw const FormatException('bad findings');
    baselineEntries = findingsEl
        .map((e) => _BaselineEntry(
              (e as Map<String, Object?>)['ruleId'] as String? ?? '',
              e['variable'] as String? ?? '',
              (e['files'] as List? ?? []).whereType<String>().toList(),
            ))
        .toList();
  } catch (e) {
    err('warning Could not read baseline $baselinePath: $e\n');
    return (findings, summary, _exitFor(findings, strict));
  }

  final kept = findings
      .where((f) => !baselineEntries.any((b) => _entryMatches(b, _fingerprint(f, rootDir))))
      .toList();
  final suppressed = findings.length - kept.length;
  if (suppressed > 0) {
    err('info $suppressed finding${suppressed == 1 ? '' : 's'} suppressed by baseline\n');
  }

  final newSummary = _recomputeSummary(summary, kept);
  return (kept, newSummary, _exitFor(kept, strict));
}

AuditSummary _recomputeSummary(AuditSummary summary, List<Finding> findings) {
  final errors = findings.where((f) => f.severity == Severity.error).length;
  final warnings = findings.where((f) => f.severity == Severity.warning).length;
  final infos = findings.where((f) => f.severity == Severity.info).length;
  return AuditSummary(
    filesScanned: summary.filesScanned,
    variablesFound: summary.variablesFound,
    errors: errors,
    warnings: warnings,
    infos: infos,
    total: findings.length,
  );
}

int _exitFor(List<Finding> findings, bool strict) {
  final errors = findings.any((f) => f.severity == Severity.error);
  final warnings = findings.any((f) => f.severity == Severity.warning);
  return errors || (strict && warnings) ? 1 : 0;
}

void _writeBaseline(List<Finding> findings, String baselinePath, String rootDir) {
  final fullPath = _resolvePath(rootDir, baselinePath);
  final baseline = JsonObject()
    ..add('version', 1)
    ..add('findings', findings.map((f) {
      final fp = _fingerprint(f, rootDir);
      return JsonObject()
        ..add('ruleId', fp.ruleId)
        ..add('variable', fp.variable)
        ..add('files', fp.files);
    }).toList());
  Directory(dirname(fullPath)).createSync(recursive: true);
  File(fullPath).writeAsStringSync('${jsonPretty(baseline)}\n');
  err('info Wrote baseline to $baselinePath\n');
}

String _resolvePath(String rootDir, String p) =>
    isAbsolutePath(p) ? p : joinPath(rootDir, p);
