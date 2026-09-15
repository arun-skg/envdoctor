/// `envdoctor snapshot-diff <a> <b>` — compare two runtime snapshots.
library;

import 'dart:io';

import '../core/exit_codes.dart';
import '../models/runtime_snapshot.dart';
import '../runtime/compare.dart';
import '../runtime/token.dart';
import '../utils/json.dart';
import '../utils/paths.dart';
import 'shared.dart';

class SnapshotDiffOptions {
  final String rootDir;
  final String a;
  final String b;
  final bool json;

  SnapshotDiffOptions({
    required this.rootDir,
    required this.a,
    required this.b,
    this.json = false,
  });
}

/// Resolve a positional arg that may be a token string or a file path.
RuntimeSnapshot _loadSnapshot(String rootDir, String arg) {
  if (arg.trim().startsWith(tokenPrefix)) {
    return decodeToken(arg);
  }
  final file = _resolvePath(rootDir, arg);
  if (!File(file).existsSync()) {
    throw SnapshotTokenException(
        'Not a snapshot token, and file not found: $arg');
  }
  return parseSnapshotJson(File(file).readAsStringSync());
}

String _resolvePath(String rootDir, String p) =>
    isAbsolutePath(p) ? p : joinPath(rootDir, p);

int runSnapshotDiff(SnapshotDiffOptions opts) {
  final RuntimeSnapshot a;
  final RuntimeSnapshot b;
  try {
    a = _loadSnapshot(opts.rootDir, opts.a);
  } catch (e) {
    err('error ${_message(e)}\n');
    return ExitCodes.exitUsage;
  }
  try {
    b = _loadSnapshot(opts.rootDir, opts.b);
  } catch (e) {
    err('error ${_message(e)}\n');
    return ExitCodes.exitUsage;
  }

  final diff = compareSnapshots(a, b);

  if (opts.json) {
    out('${_diffToJson(diff, diff.equivalent ? 0 : 1)}\n');
    return diff.equivalent ? ExitCodes.exitOk : ExitCodes.exitIssues;
  }

  _renderHuman(diff);
  return diff.equivalent ? ExitCodes.exitOk : ExitCodes.exitIssues;
}

String _message(Object e) => e is SnapshotTokenException ? e.message : e.toString();

String _diffToJson(RuntimeDiff diff, int exitCode) {
  final globals = diff.globals.map((g) {
    final obj = JsonObject()
      ..add('ecosystem', g.ecosystem)
      ..add('name', g.name)
      ..add('status', g.status.str);
    if (g.a != null) obj.add('a', g.a);
    if (g.b != null) obj.add('b', g.b);
    return obj;
  }).toList();

  final tools = diff.tools.map((t) {
    final obj = JsonObject()
      ..add('name', t.name)
      ..add('status', t.status.str);
    if (t.a != null) obj.add('a', t.a);
    if (t.b != null) obj.add('b', t.b);
    return obj;
  }).toList();

  // exitCode first, matching the reference CLI's key order.
  return jsonPretty(JsonObject()
    ..add('exitCode', exitCode)
    ..add('os', JsonObject()
      ..add('status', diff.os.status.str)
      ..add('a', diff.os.a)
      ..add('b', diff.os.b))
    ..add('tools', tools)
    ..add('pathReordered', diff.pathReordered)
    ..add('pathOnlyA', diff.pathOnlyA)
    ..add('pathOnlyB', diff.pathOnlyB)
    ..add('globals', globals)
    ..add('envFlagOnlyA', diff.envFlagOnlyA)
    ..add('envFlagOnlyB', diff.envFlagOnlyB)
    ..add('equivalent', diff.equivalent));
}

void _renderHuman(RuntimeDiff diff) {
  const title = 'RUNTIME DIFF';
  out('$title\n');
  out('${'─' * (title.length * 2)}\n\n');
  out('  A → B\n\n');

  if (diff.os.status == RuntimeStatus.same) {
    out('  ✓ OS  ${diff.os.a}\n\n');
  } else {
    out('  ⚠ OS  ${diff.os.a} → ${diff.os.b}\n\n');
  }

  out('  Tools\n');
  for (final t in diff.tools) {
    switch (t.status) {
      case RuntimeStatus.same:
        out('  ✓ ${t.name.padRight(8)} ${t.a ?? ''}\n');
      case RuntimeStatus.different:
        out('  ⚠ ${t.name.padRight(8)} ${t.a} → ${t.b}\n');
      case RuntimeStatus.onlyA:
        out('  ❌ ${t.name.padRight(8)} missing in B (A: ${t.a})\n');
      case RuntimeStatus.onlyB:
        out('  ❌ ${t.name.padRight(8)} missing in A (B: ${t.b})\n');
    }
  }

  if (diff.pathReordered || diff.pathOnlyA.isNotEmpty || diff.pathOnlyB.isNotEmpty) {
    out('\n  PATH\n');
    if (diff.pathReordered) {
      out('  ⚠ same entries, different order\n');
    }
    for (final p in diff.pathOnlyA) {
      out('  ❌ only in A: $p\n');
    }
    for (final p in diff.pathOnlyB) {
      out('  ❌ only in B: $p\n');
    }
  }

  if (diff.globals.isNotEmpty) {
    out('\n  Globals\n');
    for (final g in diff.globals) {
      final label = '${g.ecosystem}:${g.name}';
      switch (g.status) {
        case RuntimeStatus.different:
          out('  ⚠ $label  ${g.a ?? ''} → ${g.b ?? ''}\n');
        case RuntimeStatus.onlyA:
          out('  ❌ $label  missing in B\n');
        case RuntimeStatus.onlyB:
          out('  ❌ $label  missing in A\n');
        case RuntimeStatus.same:
          break;
      }
    }
  }

  out(diff.equivalent
      ? '\n  ✓ runtimes are equivalent\n'
      : '\n  ✗ runtime drift detected\n');
}
