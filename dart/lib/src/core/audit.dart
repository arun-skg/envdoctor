import '../config/config.dart';
import '../models/finding.dart';
import '../models/project_model.dart';
import 'exit_codes.dart';
import '../detectors/detector.dart';
import '../detectors/duplicates.dart';
import '../detectors/environment_diff.dart';
import '../detectors/missing.dart';
import '../detectors/public_prefix.dart';
import '../detectors/schema_validation.dart';
import '../detectors/type_mismatch.dart';
import '../detectors/typo.dart';
import '../detectors/undefined_source.dart';
import '../detectors/unused.dart';
import '../detectors/weak_secret.dart';

/// Detector ids in a well-known order. The order here is the order
/// findings are produced.
List<Detector> allDetectors() => [
      MissingDetector(),
      UnusedDetector(),
      UndefinedSourceDetector(),
      DuplicatesDetector(),
      EnvironmentDiffDetector(),
      TypeMismatchDetector(),
      PublicPrefixDetector(),
      WeakSecretDetector(),
      TypoDetector(),
      SchemaValidationDetector(),
    ];

class AuditOptions {
  final bool strict;
  final List<String> only;
  final Map<String, RuleSeverity> rules;

  AuditOptions({this.strict = false, this.only = const [], this.rules = const {}});
}

/// The audit engine is fully format-agnostic: it takes a [ProjectModel] and
/// returns an [AuditResult]. Detectors run in a stable order and their
/// findings are aggregated; the exit code is derived from severity (and
/// `strict`).
AuditResult runAudit(ProjectModel model, AuditOptions options) {
  final index = IndexedModel.buildIndex(model);

  final detectors =
      options.only.isNotEmpty ? allDetectors().where((d) => options.only.contains(d.id)).toList() : allDetectors();

  var findings = <Finding>[];
  for (final d in detectors) {
    findings.addAll(d.detect(index));
  }

  findings = applyIgnores(findings, model);
  findings = applyRuleSeverities(findings, options.rules);

  final errors = findings.where((f) => f.severity == Severity.error).length;
  final warnings = findings.where((f) => f.severity == Severity.warning).length;
  final infos = findings.where((f) => f.severity == Severity.info).length;
  final summary = AuditSummary(
    filesScanned: model.allFiles.length,
    variablesFound: _distinctVariableCount(model),
    errors: errors,
    warnings: warnings,
    infos: infos,
    total: findings.length,
  );

  final exitCode =
      ExitCodes.auditExitCode(ExitContext(findings: findings, strict: options.strict));

  return AuditResult(findings: findings, summary: summary, exitCode: exitCode);
}

/// Build a map of variable name → set of ignored rule ids from inline comments.
Map<String, Set<String>> _buildIgnoredRulesByName(ProjectModel model) {
  final ignored = <String, Set<String>>{};
  for (final file in model.envFiles) {
    if (file.environment == 'example') continue;
    for (final v in file.variables) {
      final rules = v.ignoreRules;
      if (rules == null || rules.isEmpty) continue;
      final set = ignored.putIfAbsent(v.name, () => <String>{});
      set.addAll(rules);
    }
  }
  return ignored;
}

/// Drop findings that are ignored inline in env files.
List<Finding> applyIgnores(List<Finding> findings, ProjectModel model) {
  final ignored = _buildIgnoredRulesByName(model);
  return findings.where((f) {
    final rules = ignored[f.variable];
    return !(rules != null && rules.contains(f.ruleId));
  }).toList();
}

/// Apply per-detector severity overrides from config. Disabled rules are dropped.
List<Finding> applyRuleSeverities(
    List<Finding> findings, Map<String, RuleSeverity> rules) {
  final result = <Finding>[];
  for (final f in findings) {
    final override = rules[f.ruleId];
    if (override == null) {
      result.add(f);
      continue;
    }
    switch (override) {
      case RuleSeverity.off:
        break;
      case RuleSeverity.error:
        final clone = f.clone()..severity = Severity.error;
        result.add(clone);
      case RuleSeverity.warning:
        final clone = f.clone()..severity = Severity.warning;
        result.add(clone);
    }
  }
  return result;
}

int _distinctVariableCount(ProjectModel model) {
  final names = <String>{};
  for (final file in model.allFiles) {
    for (final v in file.variables) {
      names.add(v.name);
    }
    for (final v in file.usages) {
      names.add(v.name);
    }
  }
  return names.length;
}
