/// Pure comparison of two runtime snapshots. `capturedAt` is ignored.
library;

import '../models/runtime_snapshot.dart';

enum RuntimeStatus {
  same,
  different,
  onlyA,
  onlyB;

  String get str => switch (this) {
        RuntimeStatus.same => 'same',
        RuntimeStatus.different => 'different',
        RuntimeStatus.onlyA => 'onlyA',
        RuntimeStatus.onlyB => 'onlyB',
      };
}

class OsDiff {
  RuntimeStatus status;
  String a;
  String b;
  OsDiff({this.status = RuntimeStatus.same, this.a = '', this.b = ''});
}

class ToolDiff {
  final String name;
  final RuntimeStatus status;
  final String? a;
  final String? b;
  ToolDiff({required this.name, required this.status, this.a, this.b});
}

class GlobalDiff {
  final String ecosystem;
  final String name;
  final RuntimeStatus status;
  final String? a;
  final String? b;
  GlobalDiff({
    required this.ecosystem,
    required this.name,
    required this.status,
    this.a,
    this.b,
  });
}

class RuntimeDiff {
  OsDiff os;
  List<ToolDiff> tools;
  bool pathReordered;
  List<String> pathOnlyA;
  List<String> pathOnlyB;
  List<GlobalDiff> globals;
  List<String> envFlagOnlyA;
  List<String> envFlagOnlyB;
  bool equivalent;

  RuntimeDiff({
    OsDiff? os,
    List<ToolDiff>? tools,
    this.pathReordered = false,
    List<String>? pathOnlyA,
    List<String>? pathOnlyB,
    List<GlobalDiff>? globals,
    List<String>? envFlagOnlyA,
    List<String>? envFlagOnlyB,
    this.equivalent = false,
  })  : os = os ?? OsDiff(),
        tools = tools ?? [],
        pathOnlyA = pathOnlyA ?? [],
        pathOnlyB = pathOnlyB ?? [],
        globals = globals ?? [],
        envFlagOnlyA = envFlagOnlyA ?? [],
        envFlagOnlyB = envFlagOnlyB ?? [];
}

RuntimeStatus _statusFor(String? a, String? b) {
  if (a != null && b != null) return a == b ? RuntimeStatus.same : RuntimeStatus.different;
  return a != null ? RuntimeStatus.onlyA : RuntimeStatus.onlyB;
}

List<ToolDiff> _diffTools(RuntimeSnapshot a, RuntimeSnapshot b) {
  final av = {for (final t in a.tools) t.tool: t.version};
  final bv = {for (final t in b.tools) t.tool: t.version};
  final names = <String>{...av.keys, ...bv.keys}.toList()..sort();
  return names
      .map((name) => ToolDiff(
            name: name,
            status: _statusFor(av[name], bv[name]),
            a: av[name],
            b: bv[name],
          ))
      .toList();
}

List<GlobalDiff> _diffGlobals(RuntimeSnapshot a, RuntimeSnapshot b) {
  final ecosystems = <String>{...a.globals.keys, ...b.globals.keys}.toList()..sort();
  final result = <GlobalDiff>[];
  for (final eco in ecosystems) {
    Map<String, String> index(List<GlobalPackage>? list) =>
        {for (final p in list ?? <GlobalPackage>[]) p.name: p.version};
    final av = index(a.globals[eco]);
    final bv = index(b.globals[eco]);
    final names = <String>{...av.keys, ...bv.keys};
    for (final name in names) {
      final status = _statusFor(av[name], bv[name]);
      if (status == RuntimeStatus.same) continue;
      result.add(GlobalDiff(
        ecosystem: eco,
        name: name,
        status: status,
        a: av[name],
        b: bv[name],
      ));
    }
  }
  result.sort((x, y) => x.name.compareTo(y.name));
  return result;
}

/// Set difference preserving A's order.
List<String> _onlyIn(List<String> a, List<String> b) {
  final set = b.toSet();
  return a.where((x) => !set.contains(x)).toList();
}

/// Pure comparison of two runtime snapshots. `capturedAt` is ignored.
RuntimeDiff compareSnapshots(RuntimeSnapshot a, RuntimeSnapshot b) {
  final tools = _diffTools(a, b);
  final pathOnlyA = _onlyIn(a.path, b.path);
  final pathOnlyB = _onlyIn(b.path, a.path);
  final pathReordered =
      pathOnlyA.isEmpty && pathOnlyB.isEmpty && a.path.join('\x00') != b.path.join('\x00');
  final globals = _diffGlobals(a, b);
  final envFlagOnlyA = _onlyIn(a.envFlagNames, b.envFlagNames);
  final envFlagOnlyB = _onlyIn(b.envFlagNames, a.envFlagNames);

  final osSame = a.os.platform == b.os.platform &&
      a.os.arch == b.os.arch &&
      a.os.release == b.os.release;
  String fmtOs(RuntimeSnapshot s) => '${s.os.platform}/${s.os.arch} ${s.os.release}';

  final equivalent = tools.every((t) => t.status == RuntimeStatus.same) &&
      !pathReordered &&
      pathOnlyA.isEmpty &&
      pathOnlyB.isEmpty &&
      globals.isEmpty;

  return RuntimeDiff(
    os: OsDiff(
      status: osSame ? RuntimeStatus.same : RuntimeStatus.different,
      a: fmtOs(a),
      b: fmtOs(b),
    ),
    tools: tools,
    pathReordered: pathReordered,
    pathOnlyA: pathOnlyA,
    pathOnlyB: pathOnlyB,
    globals: globals,
    envFlagOnlyA: envFlagOnlyA,
    envFlagOnlyB: envFlagOnlyB,
    equivalent: equivalent,
  );
}
