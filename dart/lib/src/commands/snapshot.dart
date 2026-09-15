/// `envdoctor snapshot` — capture this machine's live runtime.
library;

import 'dart:convert';
import 'dart:io';

import '../core/exit_codes.dart';
import '../models/runtime_snapshot.dart';
import '../runtime/capture.dart';
import '../runtime/token.dart';
import '../utils/json.dart';
import '../utils/paths.dart';
import 'shared.dart';

class SnapshotOptions {
  final String rootDir;
  final String? output;
  final bool token;
  final bool json;
  final bool globals;

  SnapshotOptions({
    required this.rootDir,
    this.output,
    this.token = false,
    this.json = false,
    this.globals = false,
  });
}

int runSnapshot(SnapshotOptions opts) {
  final snapshot = captureSnapshot(globals: opts.globals);

  if (opts.output != null) {
    final dest = _resolvePath(opts.rootDir, opts.output!);
    File(dest).writeAsStringSync('${_snapshotJsonPretty(snapshot)}\n');
    err('✓ Snapshot written to ${opts.output}\n');
  }

  if (opts.json) {
    out('${_snapshotJsonPretty(snapshot)}\n');
    return ExitCodes.exitOk;
  }

  if (opts.token) {
    out('${encodeToken(snapshot)}\n');
    return ExitCodes.exitOk;
  }

  // Human summary.
  const title = 'RUNTIME SNAPSHOT';
  out('$title\n');
  out('${'─' * (title.length * 2)}\n\n');
  out('  OS  ${snapshot.os.platform}/${snapshot.os.arch} ${snapshot.os.release}\n\n');

  out('  Tools\n');
  if (snapshot.tools.isEmpty) {
    out('  none detected\n');
  } else {
    for (final t in snapshot.tools) {
      out('  ✓ ${t.tool.padRight(8)} ${t.version}  ${t.resolvedFrom}\n');
    }
  }

  out('\n  PATH (${snapshot.path.length} entries)\n');
  final shown = snapshot.path.take(12).toList();
  for (var i = 0; i < shown.length; i++) {
    out('  ${(i + 1).toString().padLeft(2)}  ${shown[i]}\n');
  }
  if (snapshot.path.length > 12) {
    out('  … ${snapshot.path.length - 12} more\n');
  }

  final ecosystems = snapshot.globals.keys.toList();
  if (ecosystems.isNotEmpty) {
    out('\n  Globals\n');
    for (final eco in ecosystems) {
      out('  $eco: ${snapshot.globals[eco]!.length} packages\n');
    }
  } else if (!opts.globals) {
    out('\n  Globals omitted — pass --globals to include the package inventory.\n');
  }

  out(
      '\n  Share with:  envdoctor snapshot --token   ·   compare with:  envdoctor snapshot-diff <a> <b>\n');

  return ExitCodes.exitOk;
}

String _resolvePath(String rootDir, String p) =>
    isAbsolutePath(p) ? p : joinPath(rootDir, p);

/// Pretty-print the same shape the token codec emits compactly.
String _snapshotJsonPretty(RuntimeSnapshot snapshot) {
  final compact = snapshotToJson(snapshot);
  return jsonPretty(_toPlain(jsonDecode(compact)));
}

Object? _toPlain(Object? el) => switch (el) {
      Map<String, Object?> map => JsonObject()
        ..entries.addAll(map.entries.map((e) => (e.key, _toPlain(e.value)))),
      Map map => JsonObject()
        ..entries.addAll(map.entries.map((e) => (e.key.toString(), _toPlain(e.value)))),
      List list => list.map(_toPlain).toList(),
      _ => el,
    };
