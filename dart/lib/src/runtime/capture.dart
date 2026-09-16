/// Live-machine runtime snapshot capture. Captures the current machine's OS,
/// installed tool versions, `$PATH`, opt-in global package inventory, and the
/// *names* of non-secret environment variables. Secret-looking names are
/// dropped, never masked, and values are never captured.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../models/environment_variable.dart';
import '../models/runtime_snapshot.dart';

/// Tools probed by default. Order here is the display order before sorting.
const List<(String, List<String>)> toolProbes = [
  ('node', ['-v']),
  ('python3', ['--version']),
  ('python', ['--version']),
  ('go', ['version']),
  ('rustc', ['-V']),
  ('java', ['-version']),
  ('ruby', ['-v']),
  ('php', ['-v']),
  ('perl', ['-v']),
  ('cc', ['--version']),
  ('git', ['--version']),
];

final RegExp _versionRe = RegExp(r'(\d+\.\d+(?:\.\d+)?)');

/// Collapse a leading `$HOME` to `~` so snapshots don't leak usernames and
/// stay comparable across machines.
String collapseHome(String p) {
  final home = Platform.environment['HOME'] ?? '';
  if (home.isNotEmpty && (p == home || p.startsWith('$home/'))) {
    return '~${p.substring(home.length)}';
  }
  return p;
}

/// Ordered, de-duplicated `$PATH` entries with `$HOME` collapsed.
List<String> collectPath() {
  final raw = Platform.environment['PATH'] ?? '';
  final seen = <String>{};
  final result = <String>[];
  for (final part in raw.split(':')) {
    if (part.isEmpty) continue;
    final entry = collapseHome(part);
    if (seen.add(entry)) result.add(entry);
  }
  return result;
}

/// Non-secret env var NAMES only. Secret-looking names are dropped, not masked.
List<String> collectEnvFlagNames() {
  final names = Platform.environment.keys
      .where((name) => !EnvironmentVariable.isSecretName(name))
      .toList();
  names.sort();
  return names;
}

String? _run(String tool, List<String> args, {bool redirectErr = true}) {
  try {
    final result = Process.runSync(
      tool,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final stdout = result.stdout is String ? result.stdout as String : '';
    final stderr = result.stderr is String ? result.stderr as String : '';
    return stdout + (redirectErr ? stderr : '');
  } catch (_) {
    return null;
  }
}

/// Probe one CLI's version; returns null when the tool isn't installed.
String? probeVersion(String tool, List<String> args) {
  final output = _run(tool, args);
  if (output == null) return null;
  final match = _versionRe.firstMatch(output);
  return match?.group(1);
}

/// Locate which PATH directory a command resolves from, `$HOME` collapsed.
String resolveFrom(String tool) {
  final stdout = _run(Platform.isWindows ? 'where' : 'which', [tool], redirectErr: false);
  if (stdout == null) return '';
  final lines = stdout
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';
  final trimmed = lines.first.trim();
  final idx = trimmed.lastIndexOf('/');
  final dir = idx < 0 ? trimmed : trimmed.substring(0, idx);
  return collapseHome(dir);
}

/// Probe every known tool; only installed ones appear, sorted by name.
List<ToolInfo> collectTools() {
  final tools = <ToolInfo>[];
  for (final (tool, args) in toolProbes) {
    final version = probeVersion(tool, args);
    if (version == null) continue;
    tools.add(ToolInfo(tool: tool, version: version, resolvedFrom: resolveFrom(tool)));
  }
  tools.sort((a, b) => a.tool.compareTo(b.tool));
  return tools;
}

/// Global package inventory, opt-in because it is slow. Best-effort per
/// ecosystem (currently npm).
Map<String, List<GlobalPackage>> collectGlobals() {
  final globals = <String, List<GlobalPackage>>{};
  final stdout = _run('npm', ['ls', '-g', '--depth=0', '--json'], redirectErr: false);
  if (stdout != null) {
    final pkgs = parseNpmGlobals(stdout);
    if (pkgs.isNotEmpty) globals['npm'] = pkgs;
  }
  return globals;
}

/// Parse `npm ls -g --json` into a name/version list; tolerant of partial JSON.
List<GlobalPackage> parseNpmGlobals(String stdout) {
  try {
    final parsed = jsonDecode(stdout);
    if (parsed is! Map<String, Object?>) return [];
    final deps = parsed['dependencies'];
    if (deps is! Map<String, Object?>) return [];
    final pkgs = deps.entries
        .map((e) => GlobalPackage(e.key, (e.value as Map?)?['version'] as String? ?? ''))
        .toList();
    pkgs.sort((a, b) => a.name.compareTo(b.name));
    return pkgs;
  } catch (_) {
    return [];
  }
}

/// OS release string (`uname -r` on unix), best-effort.
String osRelease() {
  final stdout = _run('uname', ['-r'], redirectErr: false);
  final trimmed = stdout?.trim();
  return trimmed == null || trimmed.isEmpty ? 'unknown' : trimmed;
}

/// OS/arch strings matching Node's `process.platform` / `process.arch`
/// (the reference CLI's snapshot shape).
String osPlatform() => switch (Platform.operatingSystem) {
      'macos' => 'darwin',
      'linux' => 'linux',
      'windows' => 'win32',
      _ => Platform.operatingSystem,
    };

String osArch() {
  final abi = Abi.current().toString().toLowerCase();
  if (abi.contains('arm64')) return 'arm64';
  if (abi.contains('x86_64') || abi.contains('x64')) return 'x64';
  if (abi.contains('i386') || abi.contains('ia32')) return 'ia32';
  if (abi.contains('arm')) return 'arm';
  return 'unknown';
}

/// Capture this machine's live runtime. `globals` opts into the slow
/// package inventory.
RuntimeSnapshot captureSnapshot({bool globals = false}) {
  return RuntimeSnapshot(
    schema: snapshotSchema,
    capturedAt: DateTime.now().toUtc().toIso8601String(),
    os: OsInfo(platform: osPlatform(), arch: osArch(), release: osRelease()),
    tools: collectTools(),
    path: collectPath(),
    globals: globals ? collectGlobals() : {},
    envFlagNames: collectEnvFlagNames(),
  );
}
