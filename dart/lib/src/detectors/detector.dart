import '../models/environment_file.dart';
import '../models/finding.dart';
import '../models/origin.dart';
import '../models/project_model.dart';
import '../models/variable_type.dart';

/// A concrete definition of a variable in one file.
class Definition {
  final String name;
  final String? value;
  final VariableType type;
  final bool isSecret;
  final String? environment;
  final Origin origin;

  Definition({
    required this.name,
    this.value,
    required this.type,
    required this.isSecret,
    this.environment,
    required this.origin,
  });
}

abstract class Detector {
  String get id;
  String get name;
  String get description;
  List<Finding> detect(IndexedModel index);
}

typedef SortKey = (String, int);

SortKey originKey(Origin o) => (o.filePath, o.line ?? 0x7FFFFFFF);

/// Stable ordering key for a set of definitions: the earliest (file, line)
/// they were declared at.
SortKey defSortKey(List<Definition> defs) {
  if (defs.isEmpty) return ('', 0);
  SortKey best = originKey(defs.first.origin);
  for (final d in defs.skip(1)) {
    final k = originKey(d.origin);
    if (compareKeys(k, best) < 0) best = k;
  }
  return best;
}

/// Stable ordering key for a set of origins: the earliest (file, line).
SortKey originSortKey(List<Origin> origins) {
  if (origins.isEmpty) return ('', 0);
  SortKey best = originKey(origins.first);
  for (final o in origins.skip(1)) {
    final k = originKey(o);
    if (compareKeys(k, best) < 0) best = k;
  }
  return best;
}

int compareKeys(SortKey a, SortKey b) {
  final cmp = a.$1.compareTo(b.$1);
  return cmp != 0 ? cmp : a.$2.compareTo(b.$2);
}

/// Emit a detector's entries in the stable (file, line, name) order shared by
/// the reference CLI's deterministic output.
List<MapEntry<String, List<T>>> sortedEntries<T>(
    Map<String, List<T>> map, SortKey Function(List<T>) keyOf) {
  final entries = map.entries.toList();
  entries.sort((a, b) {
    final cmp = compareKeys(keyOf(a.value), keyOf(b.value));
    return cmp != 0 ? cmp : a.key.compareTo(b.key);
  });
  return entries;
}

/// The format-agnostic view detectors operate on. Built once so detectors
/// never scan raw files and never repeat the same work.
class IndexedModel {
  final ProjectModel model;
  final Map<String, List<Definition>> envDefinitions;
  final Map<String, List<Definition>> composeDefinitions;
  final Map<String, List<Definition>> actionDefinitions;
  final Map<String, List<Definition>> k8sDefinitions;
  final Map<String, List<Origin>> usages;
  final Map<String, List<Origin>> sourceUsages;
  final Set<String> exampleNames;
  final List<String> envLabels;

  IndexedModel({
    required this.model,
    Map<String, List<Definition>>? envDefinitions,
    Map<String, List<Definition>>? composeDefinitions,
    Map<String, List<Definition>>? actionDefinitions,
    Map<String, List<Definition>>? k8sDefinitions,
    Map<String, List<Origin>>? usages,
    Map<String, List<Origin>>? sourceUsages,
    Set<String>? exampleNames,
    List<String>? envLabels,
  })  : envDefinitions = envDefinitions ?? {},
        composeDefinitions = composeDefinitions ?? {},
        actionDefinitions = actionDefinitions ?? {},
        k8sDefinitions = k8sDefinitions ?? {},
        usages = usages ?? {},
        sourceUsages = sourceUsages ?? {},
        exampleNames = exampleNames ?? {},
        envLabels = envLabels ?? [];

  static IndexedModel buildIndex(ProjectModel model) {
    final envDefinitions = <String, List<Definition>>{};
    final composeDefinitions = <String, List<Definition>>{};
    final actionDefinitions = <String, List<Definition>>{};
    final k8sDefinitions = <String, List<Definition>>{};
    final usages = <String, List<Origin>>{};
    final sourceUsages = <String, List<Origin>>{};
    final exampleNames = <String>{};
    final envLabels = <String>[];

    void pushDef(Map<String, List<Definition>> map, Definition def) {
      map.putIfAbsent(def.name, () => []).add(def);
    }

    void pushOrigin(Map<String, List<Origin>> map, String name, Origin origin) {
      map.putIfAbsent(name, () => []).add(origin);
    }

    // Process env files.
    for (final file in model.envFiles) {
      if (file.environment == 'example') {
        // .env.example documents what *should* exist but is not a
        // runtime value. Add to exampleNames only.
        for (final v in file.variables) {
          exampleNames.add(v.name);
        }
        continue;
      }

      if (file.environment != null && !envLabels.contains(file.environment)) {
        envLabels.add(file.environment!);
      }

      for (final v in file.variables) {
        for (final origin in v.origins) {
          pushDef(
            envDefinitions,
            Definition(
              name: v.name,
              value: v.value,
              type: v.type,
              isSecret: v.isSecret,
              environment: file.environment,
              origin: origin,
            ),
          );
        }
      }

      for (final v in file.usages) {
        for (final origin in v.origins) {
          pushOrigin(usages, v.name, origin);
        }
      }
    }

    void processFiles(
      List<EnvironmentFile> files,
      OriginFormat format,
      Map<String, List<Definition>> map,
    ) {
      for (final file in files) {
        for (final v in file.variables) {
          for (final origin in v.origins) {
            pushDef(
              map,
              Definition(
                name: v.name,
                value: v.value,
                type: v.type,
                isSecret: v.isSecret,
                environment: file.environment,
                origin: origin,
              ),
            );
          }
        }
        for (final v in file.usages) {
          for (final origin in v.origins) {
            pushOrigin(usages, v.name, origin);
          }
        }
      }
    }

    processFiles(model.composeFiles, OriginFormat.dockerCompose, composeDefinitions);
    processFiles(model.actionFiles, OriginFormat.githubActions, actionDefinitions);
    processFiles(model.k8sFiles, OriginFormat.kubernetes, k8sDefinitions);

    // Process source files.
    for (final file in model.sourceFiles) {
      for (final v in file.usages) {
        for (final origin in v.origins) {
          pushOrigin(usages, v.name, origin);
          pushOrigin(sourceUsages, v.name, origin);
        }
      }
    }

    return IndexedModel(
      model: model,
      envDefinitions: envDefinitions,
      composeDefinitions: composeDefinitions,
      actionDefinitions: actionDefinitions,
      k8sDefinitions: k8sDefinitions,
      usages: usages,
      sourceUsages: sourceUsages,
      exampleNames: exampleNames,
      envLabels: envLabels,
    );
  }
}
