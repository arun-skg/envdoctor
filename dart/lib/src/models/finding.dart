/// Model types shared across envdoctor.
library;

import 'origin.dart';

enum Severity {
  error,
  warning,
  info;

  String get str => switch (this) {
        Severity.error => 'error',
        Severity.warning => 'warning',
        Severity.info => 'info',
      };
}

/// A single problem found by a detector. `message` is written for humans and
/// must never contain a variable value.
class Finding {
  final String id;
  final String ruleId;
  Severity severity;
  final String variable;
  final String message;
  final List<Origin> locations;

  Finding({
    required this.ruleId,
    required this.severity,
    required this.variable,
    required this.message,
    required this.locations,
  }) : id = '$ruleId.$variable';

  Finding clone() => Finding(
        ruleId: ruleId,
        severity: severity,
        variable: variable,
        message: message,
        locations: locations.map((o) => Origin.clone(o)).toList(),
      );

  static Finding make(
    String ruleId,
    Severity severity,
    String variable,
    String message,
    List<Origin> locations,
  ) =>
      Finding(
          ruleId: ruleId,
          severity: severity,
          variable: variable,
          message: message,
          locations: locations);
}

class AuditSummary {
  int filesScanned;
  int variablesFound;
  int errors;
  int warnings;
  int infos;
  int total;

  AuditSummary({
    this.filesScanned = 0,
    this.variablesFound = 0,
    this.errors = 0,
    this.warnings = 0,
    this.infos = 0,
    this.total = 0,
  });

  AuditSummary clone() => AuditSummary(
        filesScanned: filesScanned,
        variablesFound: variablesFound,
        errors: errors,
        warnings: warnings,
        infos: infos,
        total: total,
      );
}

class AuditResult {
  final List<Finding> findings;
  final AuditSummary summary;
  final int exitCode;

  AuditResult({required this.findings, required this.summary, required this.exitCode});
}

class ExitContext {
  final List<Finding> findings;
  final bool strict;

  ExitContext({required this.findings, required this.strict});
}
