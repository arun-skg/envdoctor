/// Portable snapshot token: `base64url(gzip(json))` with an `envd1:` prefix.
library;

import 'dart:convert';
import 'dart:io';

import '../models/runtime_snapshot.dart';
import '../utils/json.dart';

const String tokenPrefix = 'envd1:';

class SnapshotTokenException implements Exception {
  final String message;
  SnapshotTokenException(this.message);
  @override
  String toString() => message;
}

/// Serialize a snapshot to compact JSON with the reference property order.
String snapshotToJson(RuntimeSnapshot snapshot) {
  final globals = JsonObject();
  for (final entry in snapshot.globals.entries) {
    globals.add(
      entry.key,
      entry.value
          .map((p) => JsonObject()
            ..add('name', p.name)
            ..add('version', p.version))
          .toList(),
    );
  }
  return jsonCompact(JsonObject()
    ..add('schema', snapshot.schema)
    ..add('capturedAt', snapshot.capturedAt)
    ..add('os', JsonObject()
      ..add('platform', snapshot.os.platform)
      ..add('arch', snapshot.os.arch)
      ..add('release', snapshot.os.release))
    ..add('tools', snapshot.tools
        .map((t) => JsonObject()
          ..add('tool', t.tool)
          ..add('version', t.version)
          ..add('resolvedFrom', t.resolvedFrom))
        .toList())
    ..add('path', snapshot.path)
    ..add('globals', globals)
    ..add('envFlagNames', snapshot.envFlagNames));
}

/// Encode a snapshot into a single-line, paste-safe token.
String encodeToken(RuntimeSnapshot snapshot) {
  final json = utf8.encode(snapshotToJson(snapshot));
  final gzipped = gzip.encode(json);
  return tokenPrefix + base64UrlEncodeNoPadding(gzipped);
}

/// Decode a token back into a snapshot. Errors clearly on malformed or
/// too-new input.
RuntimeSnapshot decodeToken(String token) {
  final trimmed = token.trim();
  if (!trimmed.startsWith(tokenPrefix)) {
    throw SnapshotTokenException(
        'Not an envdoctor snapshot token (missing envd1: prefix).');
  }

  Object? decoded;
  try {
    final gzipped = base64UrlDecodeNoPadding(trimmed.substring(tokenPrefix.length));
    decoded = jsonDecode(utf8.decode(gzip.decode(gzipped)));
  } catch (_) {
    throw SnapshotTokenException('Corrupt snapshot token: could not decode.');
  }
  final snapshot = _parseSnapshot(decoded);
  _assertReadable(snapshot);
  return snapshot;
}

/// Parse raw JSON (from a `--output` file) into a validated snapshot.
RuntimeSnapshot parseSnapshotJson(String text) {
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw SnapshotTokenException('Invalid snapshot JSON.');
  }
  final snapshot = _parseSnapshot(decoded);
  _assertReadable(snapshot);
  return snapshot;
}

/// Reject snapshots that are not runtime snapshots or come from a newer
/// schema than this build understands.
void _assertReadable(RuntimeSnapshot snapshot) {
  if (!snapshot.hasValidShape) {
    throw SnapshotTokenException('Not a runtime snapshot.');
  }
  if (snapshot.schema > snapshotSchema) {
    throw SnapshotTokenException(
        'Snapshot schema v${snapshot.schema} is newer than this envdoctor (v$snapshotSchema). Upgrade to compare it.');
  }
}

RuntimeSnapshot _parseSnapshot(Object? el) {
  if (el is! Map<String, Object?>) {
    return RuntimeSnapshot()
      ..schema = -1
      ..hasValidShape = false;
  }
  final snapshot = RuntimeSnapshot();
  final schema = el['schema'];
  if (schema is int) {
    snapshot.schema = schema;
  } else {
    snapshot.hasValidShape = false;
  }
  final capturedAt = el['capturedAt'];
  if (capturedAt is String) snapshot.capturedAt = capturedAt;
  final os = el['os'];
  if (os is Map<String, Object?>) {
    snapshot.os = OsInfo(
      platform: os['platform'] as String? ?? '',
      arch: os['arch'] as String? ?? '',
      release: os['release'] as String? ?? '',
    );
  }
  final tools = el['tools'];
  if (tools is List) {
    snapshot.tools = tools
        .whereType<Map<String, Object?>>()
        .map((t) => ToolInfo(
              tool: t['tool'] as String? ?? '',
              version: t['version'] as String? ?? '',
              resolvedFrom: t['resolvedFrom'] as String? ?? '',
            ))
        .toList();
  } else {
    snapshot.hasValidShape = false;
  }
  final path = el['path'];
  if (path is List) {
    snapshot.path = path.whereType<String>().toList();
  }
  final globals = el['globals'];
  if (globals is Map<String, Object?>) {
    for (final entry in globals.entries) {
      final list = entry.value;
      snapshot.globals[entry.key] = list is List
          ? list
              .whereType<Map<String, Object?>>()
              .map((p) => GlobalPackage(p['name'] as String? ?? '', p['version'] as String? ?? ''))
              .toList()
          : [];
    }
  }
  final flags = el['envFlagNames'];
  if (flags is List) {
    snapshot.envFlagNames = flags.whereType<String>().toList();
  }
  return snapshot;
}

String base64UrlEncodeNoPadding(List<int> data) =>
    base64Url.encode(data).replaceAll('=', '');

List<int> base64UrlDecodeNoPadding(String input) {
  var b64 = input.replaceAll('-', '+').replaceAll('_', '/');
  switch (b64.length % 4) {
    case 2:
      b64 += '==';
    case 3:
      b64 += '=';
  }
  return base64.decode(b64);
}
