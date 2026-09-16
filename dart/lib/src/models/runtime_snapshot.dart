/// Runtime snapshot model. A snapshot captures the *live* shell runtime of
/// one machine — installed tool versions, `$PATH` resolution order, optional
/// global packages, and the OS. **Values are never captured.** Only variable
/// *names* are recorded in `envFlagNames`, and names that look secret are
/// dropped entirely.
library;

/// Bumped whenever the snapshot shape changes; `snapshot-diff` refuses tokens
/// it can't read.
const int snapshotSchema = 1;

class ToolInfo {
  final String tool;
  final String version;
  final String resolvedFrom;

  ToolInfo({required this.tool, required this.version, required this.resolvedFrom});
}

class GlobalPackage {
  final String name;
  final String version;

  GlobalPackage(this.name, this.version);
}

class OsInfo {
  String platform;
  String arch;
  String release;

  OsInfo({this.platform = '', this.arch = '', this.release = ''});
}

class RuntimeSnapshot {
  int schema;
  String capturedAt;
  OsInfo os;
  List<ToolInfo> tools;
  List<String> path;
  Map<String, List<GlobalPackage>> globals;
  List<String> envFlagNames;

  /// Set when the parsed input has the minimum snapshot shape
  /// (numeric `schema`, array `tools`).
  bool hasValidShape = true;

  RuntimeSnapshot({
    this.schema = snapshotSchema,
    this.capturedAt = '',
    OsInfo? os,
    List<ToolInfo>? tools,
    List<String>? path,
    Map<String, List<GlobalPackage>>? globals,
    List<String>? envFlagNames,
  })  : os = os ?? OsInfo(),
        tools = tools ?? [],
        path = path ?? [],
        globals = globals ?? {},
        envFlagNames = envFlagNames ?? [];
}
