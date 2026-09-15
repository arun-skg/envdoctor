/// `envdoctor generate <target>` — generate files from the project model.
library;

import 'dart:io';

import '../core/pipeline.dart';
import '../generators/env_example.dart';
import '../generators/env_types.dart';
import '../generators/environment_doc.dart';
import '../generators/github_actions.dart';
import '../generators/schema.dart';
import '../utils/paths.dart';
import 'shared.dart';

enum GenerateTarget {
  envExample,
  envDoc,
  envTypes,
  configSchema,
  configTemplate,
  githubActions,
}

class GenerateOptions {
  final GenerateTarget target;
  final String rootDir;
  final String? output;

  GenerateOptions({required this.target, required this.rootDir, this.output});
}

int runGenerate(GenerateOptions opts) {
  final root = opts.rootDir;

  final context = loadProject(root);
  final model = context.model;
  final config = context.config;

  final output = switch (opts.target) {
    GenerateTarget.envExample => generateEnvExample(model, config),
    GenerateTarget.envDoc => generateEnvironmentDoc(model, config),
    GenerateTarget.envTypes => generateEnvTypes(model, config),
    GenerateTarget.configSchema => generateConfigSchema(),
    GenerateTarget.configTemplate => generateConfigTemplate(),
    GenerateTarget.githubActions => generateGithubActions(model, config),
  };

  if (opts.output != null) {
    final path =
        isAbsolutePath(opts.output!) ? opts.output! : joinPath(root, opts.output!);
    File(path).writeAsStringSync(output);
    out('Written to ${opts.output}\n');
  } else {
    out('$output\n');
  }

  return 0;
}
