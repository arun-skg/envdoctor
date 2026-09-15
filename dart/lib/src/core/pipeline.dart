/// The standard pipeline every command uses: load config → discover files →
/// assemble the normalized model.
library;

import '../config/config.dart';
import '../config/config_loader.dart';
import '../models/finding.dart';
import '../models/project_model.dart';
import 'discover.dart';
import 'model_assembler.dart';

class ProjectContext {
  final String rootDir;
  final EnvdoctorConfig config;
  final ProjectModel model;

  ProjectContext(this.rootDir, this.config, this.model);
}

/// Load a project: discover files, assemble the model, and return it
/// together with the config used.
ProjectContext loadProject(String rootDir) => loadProjectFiltered(rootDir, null);

/// Like [loadProject], but restricts the assembled model to `changed` files
/// when a set is provided (used by `scan --staged` / `--since`).
ProjectContext loadProjectFiltered(String rootDir, Set<String>? changed) {
  final config = ConfigLoader.loadConfigOrDefault(rootDir);

  final envFiles = discoverFiles(rootDir, config);
  final sourceFiles = discoverSourceFiles(rootDir, config);

  final allPaths = <String>[...envFiles, ...sourceFiles];

  if (changed != null) {
    allPaths.retainWhere(changed.contains);
  }

  final model = assembleModel(rootDir, config, allPaths);
  return ProjectContext(rootDir, config, model);
}

/// Build a summary from a list of findings and the scanned project model.
AuditSummary summarize(ProjectModel model, List<Finding> findings) {
  var errors = 0;
  var warnings = 0;
  var infos = 0;
  for (final f in findings) {
    switch (f.severity) {
      case Severity.error:
        errors++;
      case Severity.warning:
        warnings++;
      case Severity.info:
        infos++;
    }
  }
  return AuditSummary(
    filesScanned: model.allFiles.length,
    variablesFound: _distinctVariableCount(model),
    errors: errors,
    warnings: warnings,
    infos: infos,
    total: errors + warnings + infos,
  );
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
