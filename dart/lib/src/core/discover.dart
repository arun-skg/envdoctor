/// File discovery for the audit pipeline.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../config/config.dart';
import '../utils/glob.dart';
import '../utils/paths.dart';

/// Always-ignored basenames during discovery.
const List<String> alwaysIgnored = [
  'node_modules',
  '.git',
  'dist',
  'build',
  '.next',
  '.turbo',
  '.vercel',
  '.netlify',
  'coverage',
  '.nyc_output',
  'target',
  '.cargo',
  'vendor',
  'Pods',
  '.idea',
  '.vscode',
  '*.log',
  '*.tmp',
  '*.swp',
  '*.swo',
  '~*',
  '*.DS_Store',
];

/// Directories that are never descended into.
final Set<String> ignoredDirs = {
  'node_modules',
  '.git',
  'dist',
  'build',
  'coverage',
  '.next',
  '.nuxt',
  '.venv',
  'vendor',
  '.Trash',
  'Library',
  '.cache',
  '.npm',
  '.turbo',
  '.vercel',
  '.netlify',
  '.nyc_output',
  'target',
  '.cargo',
  'Pods',
  '.idea',
  '.vscode',
};

/// Git-aware file filter: tracks whether we're in a repo and can run
/// `git check-ignore` / `git diff`.
class GitFilter {
  final String root;
  final bool isRepo;

  GitFilter(this.root) : isRepo = _checkRepo(root);

  static bool _checkRepo(String root) {
    try {
      final result = Process.runSync('git', ['rev-parse', '--is-inside-work-tree'],
          workingDirectory: root, stdoutEncoding: utf8, stderrEncoding: utf8);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Should this file be skipped? Returns true to skip.
  bool shouldSkip(String path) {
    // Check always-ignored patterns first (fast path).
    final fileName = basename(path);
    for (final pattern in alwaysIgnored) {
      if (matchesGlob(pattern, fileName)) return true;
    }

    // If not a git repo, rely on patterns only.
    if (!isRepo) return false;

    final rel = relativeTo(root, path);
    if (rel == null) return false;

    // Skip if git ignores it (via .gitignore).
    try {
      final result = Process.runSync('git', ['check-ignore', '-q', rel],
          workingDirectory: root, stdoutEncoding: utf8, stderrEncoding: utf8);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Discover all files matching the configured glob patterns.
List<String> discoverFiles(String root, EnvdoctorConfig config) {
  final patterns = [
    ...config.envFilePatterns,
    ...config.composeFilePatterns,
    ...config.actionsFilePatterns,
    ...config.k8sFilePatterns,
  ].map(pathGlobToRegExp).toList();

  final gitFilter = GitFilter(root);
  final results = <String>[];

  for (final path in walkFiles(root)) {
    final rel = relativeTo(root, path);
    if (rel == null) continue;
    if (!patterns.any((re) => re.hasMatch(rel))) continue;
    if (gitFilter.shouldSkip(path)) continue;
    results.add(path);
  }

  results.sort();
  return LinkedHashSet<String>.from(results).toList();
}

/// Discover source files for usage scanning.
List<String> discoverSourceFiles(String root, EnvdoctorConfig config) {
  final extensions = config.sourceExtensions
      .map((e) => e.startsWith('.') ? e.substring(1) : e)
      .toSet();
  final gitFilter = GitFilter(root);
  final results = <String>[];

  for (final path in walkFiles(root)) {
    if (gitFilter.shouldSkip(path)) continue;
    final ext = extensionOf(path);
    if (ext.isNotEmpty && extensions.contains(ext)) results.add(path);
  }

  results.sort();
  return LinkedHashSet<String>.from(results).toList();
}

/// Walk every file under root, pruning always-ignored directories.
Iterable<String> walkFiles(String root) sync* {
  final pending = <String>[root];
  while (pending.isNotEmpty) {
    final dir = pending.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false).toList();
    } catch (_) {
      continue;
    }
    for (final entry in entries) {
      final name = basename(entry.path);
      if (entry is Directory) {
        if (!ignoredDirs.contains(name)) pending.add(entry.path);
      } else if (entry is File) {
        yield entry.path;
      }
    }
  }
}

/// Get files changed since a commit/branch (including untracked files).
List<String> changedFilesSince(String root, String since) =>
    _gitNameOnly(root, ['diff', '--name-only', since], includeUntracked: true);

/// Get currently staged files.
List<String> stagedFiles(String root) =>
    _gitNameOnly(root, ['diff', '--name-only', '--cached'], includeUntracked: false);

List<String> _gitNameOnly(String root, List<String> args,
    {required bool includeUntracked}) {
  try {
    final topLevelResult = Process.runSync(
      'git',
      ['rev-parse', '--show-toplevel'],
      workingDirectory: root,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (topLevelResult.exitCode != 0) return [];
    final topLevel = topLevelResult.stdout.trim();
    final result = Process.runSync('git', ['-C', topLevel, ...args],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    if (result.exitCode != 0) return [];
    final files = <String>[];
    final seen = <String>{};
    void addResolved(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      final full = normalizePath(
          isAbsolutePath(trimmed) ? trimmed : joinPath(topLevel, trimmed));
      if (seen.add(full)) files.add(full);
    }

    for (final line in (result.stdout as String).split('\n')) {
      addResolved(line);
    }
    if (includeUntracked) {
      try {
        final untracked = Process.runSync(
          'git',
          ['-C', topLevel, 'ls-files', '--others', '--exclude-standard'],
          workingDirectory: root,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (untracked.exitCode == 0) {
          for (final line in (untracked.stdout as String).split('\n')) {
            addResolved(line);
          }
        }
      } catch (_) {
        // ignore
      }
    }
    return files;
  } catch (_) {
    return [];
  }
}

/// True when git-aware filtering is active but no git changes were found.
bool hasNoGitChanges(String root, {bool? staged, String? since}) {
  if (staged == true) {
    return stagedFiles(root).isEmpty;
  }
  if (since != null) {
    return changedFilesSince(root, since).isEmpty;
  }
  return false;
}

final Map<String, RegExp> _pathGlobCache = {};

/// Translate a path glob (with `**`, `*`, `?`, and `{a,b}` braces) to a regex
/// matched against a root-relative, forward-slash path.
RegExp pathGlobToRegExp(String pattern) {
  final cached = _pathGlobCache[pattern];
  if (cached != null) return cached;
  final sb = StringBuffer('^');
  var i = 0;
  while (i < pattern.length) {
    final c = pattern[i];
    switch (c) {
      case '*':
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          // `**/`: zero or more whole segments; bare `**`: anything.
          if (i + 2 < pattern.length && pattern[i + 2] == '/') {
            sb.write('(?:.*/)?');
            i += 3;
          } else {
            sb.write('.*');
            i += 2;
          }
        } else {
          sb.write('[^/]*');
          i += 1;
        }
      case '?':
        sb.write('[^/]');
        i += 1;
      case '{':
        final close = pattern.indexOf('}', i + 1);
        if (close < 0) {
          sb.write(r'\{');
          i += 1;
        } else {
          final inner = pattern.substring(i + 1, close);
          final options = inner.split(',').map(RegExp.escape);
          sb.write('(?:${options.join('|')})');
          i = close + 1;
        }
      default:
        sb.write(RegExp.escape(c));
        i += 1;
    }
  }
  sb.write(r'$');
  final re = RegExp(sb.toString());
  _pathGlobCache[pattern] = re;
  return re;
}
