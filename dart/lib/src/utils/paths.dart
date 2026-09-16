/// Path helpers shared by discovery and formatters.
library;

/// Path relative to root using forward slashes; null when not under root.
String? relativeTo(String root, String path) {
  final prefix = root.endsWith('/') ? root : '$root/';
  if (path.startsWith(prefix)) return path.substring(prefix.length);
  return path == root ? '' : null;
}

/// Render a path relative to the project root when possible, falling back to
/// the absolute path.
String displayPath(String rootDir, String filePath) {
  final rel = relativeTo(rootDir, filePath);
  if (rel != null && rel.isNotEmpty) return rel;
  return filePath;
}

/// Join with forward slashes (paths are already platform-separated on the
/// platforms envdoctor supports; this normalizes for output).
String normalizePath(String p) => p.replaceAll('\\', '/');

/// True for absolute paths: POSIX `/…`, Windows drive letters, or UNC.
bool isAbsolutePath(String p) =>
    p.startsWith('/') ||
    p.startsWith('\\\\') ||
    (p.length > 2 && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p));

String basename(String p) {
  final idx = p.lastIndexOf('/');
  return idx < 0 ? p : p.substring(idx + 1);
}

String extensionOf(String p) {
  final base = basename(p);
  final dot = base.lastIndexOf('.');
  if (dot <= 0) return '';
  return base.substring(dot + 1);
}

String dirname(String p) {
  final idx = p.lastIndexOf('/');
  if (idx < 0) return '';
  return idx == 0 ? '/' : p.substring(0, idx);
}

String joinPath(String a, String b) {
  if (a.endsWith('/')) return '$a$b';
  return '$a/$b';
}
