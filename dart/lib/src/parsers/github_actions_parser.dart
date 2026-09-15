/// Parser for GitHub Actions workflow files (`.github/workflows/*.{yml,yaml}`).
///
/// Definitions come from `env:` blocks at the workflow, job, and step level.
/// `${{ secrets.NAME }}` / `${{ vars.NAME }}` and `$VAR` / `${VAR}`
/// interpolations anywhere in the file become usages.
library;

import '../models/environment_file.dart';
import '../models/environment_variable.dart';
import '../models/origin.dart';
import '../utils/paths.dart';
import 'parser.dart';
import 'yaml_facade.dart';
import 'yaml_interp.dart';

class GithubActionsParser implements Parser {
  static final RegExp _secretRefRe = RegExp(
    r'\$\{\{\s*(secrets|vars)\.([A-Za-z_][A-Za-z0-9_-]*)\s*\}\}',
  );
  static final RegExp _yamlExtRe = RegExp(r'\.(ya?ml)$');

  @override
  String get id => 'github-actions';

  @override
  bool matchPath(String filePath) {
    final base = basename(filePath);
    final isWorkflow = filePath.contains('/.github/workflows/');
    return isWorkflow && _yamlExtRe.hasMatch(base);
  }

  @override
  EnvironmentFile parse(String content, String filePath) {
    final doc = yamlLoadFirst(content);
    final variables = <EnvironmentVariable>[];
    if (doc != null) {
      _collectEnvBlocks(doc, content, filePath, variables);
    }

    final usages = <EnvironmentVariable>[];

    // ${{ secrets.X }} / ${{ vars.X }} → usages.
    for (final match in _secretRefRe.allMatches(content)) {
      final subkind = match.group(1)!;
      final name = match.group(2)!;
      final origin = Origin(
        filePath: filePath,
        line: lineForOffset(content, match.start),
        kind: OriginKind.usage,
        format: OriginFormat.githubActions,
        subkind: subkind == 'vars' ? 'vars' : 'secrets',
      );
      usages.add(EnvironmentVariable.create(name, null, [origin]));
    }

    // $VAR / ${VAR} → usages.
    for (final interp in scanInterpolations(content)) {
      final origin = Origin(
        filePath: filePath,
        line: interp.line,
        kind: OriginKind.usage,
        format: OriginFormat.githubActions,
      );
      usages.add(EnvironmentVariable.create(interp.name, null, [origin]));
    }

    return EnvironmentFile(
      filePath: filePath,
      format: FileFormat.githubActions,
      variables: EnvironmentVariable.merge(variables),
      usages: EnvironmentVariable.merge(usages),
    );
  }

  /// Recursively collect every `env:` block as definition variables.
  static void _collectEnvBlocks(
      Object? node, String content, String filePath, List<EnvironmentVariable> output) {
    if (node is List<Object?>) {
      for (final item in node) {
        _collectEnvBlocks(item, content, filePath, output);
      }
      return;
    }
    if (node is! Map<String, Object?>) return;

    final envObj = node['env'];
    if (envObj is Map<String, Object?>) {
      for (final entry in envObj.entries) {
        final key = entry.key;
        if (key.isEmpty) continue;
        final rawValue = entry.value;
        final value = rawValue == null ? null : jsString(rawValue);
        final origin = Origin(
          filePath: filePath,
          line: _lineForName(content, key),
          kind: value == null ? OriginKind.reference : OriginKind.definition,
          format: OriginFormat.githubActions,
        );
        output.add(EnvironmentVariable.create(key, value, [origin]));
      }
    }

    for (final value in node.values) {
      _collectEnvBlocks(value, content, filePath, output);
    }
  }

  /// Best-effort line lookup for an `env:` key in the raw YAML text.
  static int? _lineForName(String content, String name) {
    final escaped = RegExp.escape(name);
    final re = RegExp('^\\s*[""\']?$escaped[""\']?\\s*:', multiLine: true);
    final match = re.firstMatch(content);
    return match == null ? null : lineForOffset(content, match.start);
  }
}
