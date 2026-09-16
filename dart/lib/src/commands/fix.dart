/// `envdoctor fix` — run the audit, then regenerate the safe, generated
/// artifacts: `.env.example`, `ENVIRONMENT.md`, and (when the project uses
/// GitHub Actions secrets/vars) `.github/ENVIRONMENT.md`. Never touches real
/// `.env` files and never writes secret values. `--dry-run` previews changes.
library;

import 'dart:io';

import '../core/audit.dart';
import '../core/pipeline.dart';
import '../generators/env_example.dart';
import '../generators/env_types.dart';
import '../generators/environment_doc.dart';
import '../generators/github_actions.dart';
import '../generators/schema.dart';
import '../utils/paths.dart';
import 'shared.dart';

class FixOptions {
  final String rootDir;
  final bool dryRun;
  final bool force;
  final bool verbose;

  FixOptions({
    required this.rootDir,
    this.dryRun = false,
    this.force = false,
    this.verbose = false,
  });
}

class _PlannedFile {
  final String relPath;
  final String action; // create | update | skip
  final String content;
  _PlannedFile(this.relPath, this.action, this.content);
}

int runFix(FixOptions opts) {
  final context = loadProject(opts.rootDir);
  final audit = runAudit(
    context.model,
    AuditOptions(strict: false, rules: context.config.rules),
  );

  final checklist = collectActionsChecklist(context.model);
  final hasActionsRefs =
      checklist.secrets.isNotEmpty || checklist.vars.isNotEmpty;

  final plans = <_PlannedFile>[
    _plan(opts.rootDir, '.env.example', generateEnvExample(context.model, context.config), opts),
    _plan(opts.rootDir, 'ENVIRONMENT.md', generateEnvironmentDoc(context.model, context.config), opts),
    _plan(opts.rootDir, 'env.d.ts', generateEnvTypes(context.model, context.config), opts),
    _plan(opts.rootDir, 'envdoctor.schema.ts', generateVariableSchemaTs(context.model), opts),
  ];
  if (hasActionsRefs) {
    plans.add(_plan(opts.rootDir, joinPath('.github', 'ENVIRONMENT.md'),
        generateActionsChecklist(context.model), opts));
  }

  if (opts.dryRun) {
    out('envdoctor fix (dry run)\n\n');
    for (final plan in plans) {
      final marker = plan.action == 'create'
          ? '+'
          : plan.action == 'update'
              ? '~'
              : '·';
      out('  $marker ${plan.relPath}  ${_actionLabel(plan.action)}\n');
    }
    final pending = plans.where((p) => p.action != 'skip').length;
    out('\n  $pending change${pending == 1 ? '' : 's'} planned\n');
    return audit.exitCode;
  }

  var created = 0;
  var updated = 0;
  for (final plan in plans) {
    if (plan.action == 'skip') continue;
    final full = joinPath(opts.rootDir, plan.relPath);
    Directory(dirname(full)).createSync(recursive: true);
    File(full).writeAsStringSync(plan.content);
    if (plan.action == 'create') {
      created++;
    } else {
      updated++;
    }
  }

  out('envdoctor fix\n\n');
  for (final plan in plans) {
    if (plan.action == 'skip') {
      out('  · skipped ${plan.relPath} (exists; use --force to overwrite)\n');
    } else {
      out('  ✓ ${plan.action == 'create' ? 'created' : 'updated'} ${plan.relPath}\n');
    }
  }
  out(
      '\n  $created created, $updated updated · ${audit.summary.errors} error${audit.summary.errors == 1 ? '' : 's'} still present\n');

  return audit.exitCode;
}

_PlannedFile _plan(String rootDir, String relPath, String content, FixOptions opts) {
  final exists = File(joinPath(rootDir, relPath)).existsSync();
  if (!exists) return _PlannedFile(relPath, 'create', content);
  if (opts.force) return _PlannedFile(relPath, 'update', content);
  return _PlannedFile(relPath, 'skip', content);
}

String _actionLabel(String action) {
  if (action == 'create') return 'will create';
  if (action == 'update') return 'will update';
  return 'exists';
}
