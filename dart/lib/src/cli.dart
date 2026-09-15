/// envdoctor CLI. Each command is a thin wrapper around a `commands/*`
/// module that returns an exit code; errors are normalized to exit code 2.
library;

import 'dart:io';

import 'commands/diff.dart';
import 'commands/fix.dart';
import 'commands/generate.dart';
import 'commands/init.dart';
import 'commands/scan.dart';
import 'commands/shared.dart';
import 'commands/snapshot.dart';
import 'commands/snapshot_diff.dart';
import 'commands/sync.dart';
import 'utils/paths.dart';

const String version = '0.1.2';

const String rootHelp = '''
Usage: envdoctor [options] [command]

Local-first consistency checker for environment variables. Detects missing,
unused, duplicate, and mismatched variables across .env files, docker-compose,
GitHub Actions, and source code.

Options:
  -V, --version                                 output the version number
  -h, --help                                    display help for command

Commands:
  init [options]                                Bootstrap envdoctor: config, .env.example, and ENVIRONMENT.md.
  scan [options]                                Scan the project for environment variable inconsistencies.
  fix [options]                                 Generate safe artifacts: .env.example, ENVIRONMENT.md, and a GitHub Actions checklist.
  diff [options] <environment1> <environment2>  Compare environment variable sets across two environments.
  sync [options] <from> <to>                    Copy missing variable keys from one environment file to another with placeholders.
  snapshot [options]                            Capture this machine's live runtime (tool versions, PATH order, globals) as a portable token.
  snapshot-diff [options] <a> <b>               Compare two runtime snapshots (file paths or pasted tokens).
  help [command]                                display help for command
''';

class UsageException implements Exception {
  final String message;
  final String usage;
  final int exitCode;
  UsageException(this.message, this.usage, {this.exitCode = 2});
}

/// Cursor over a command's argument list.
class ArgCursor {
  final List<String> args;
  final String usage;
  var _i = 0;
  final List<String> positionals = [];

  ArgCursor(this.args, this.usage);

  String? next() => _i < args.length ? args[_i++] : null;

  String requireValue(String flag) {
    if (_i >= args.length) {
      throw UsageException(
          "a value is required for '$flag <VALUE>' but none was supplied", usage);
    }
    return args[_i++];
  }

  UsageException unexpected(String arg) =>
      UsageException("unexpected argument '$arg' found", usage);
}

/// Parse rules for `--only`: comma-separated, trimmed, empties dropped.
List<String> parseRules(String value) =>
    value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

String? _root;

String resolveRoot(String? input) {
  final dir = input == null ? Directory.current.path : _absolute(input);
  if (!Directory(dir).existsSync()) {
    throw UsageException('Directory not found: $dir', 'envdoctor');
  }
  if (FileSystemEntity.typeSync(dir) != FileSystemEntityType.directory) {
    throw UsageException('Not a directory: $dir', 'envdoctor');
  }
  return dir;
}

String _absolute(String p) {
  if (isAbsolutePath(p)) return _normalize(p);
  return _normalize(joinPath(Directory.current.path, p));
}

String _normalize(String p) {
  // Normalize away `.` and `..` segments without touching the filesystem.
  final isAbs = p.startsWith('/');
  final parts = p.split('/');
  final out = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else if (!isAbs) {
        out.add('..');
      }
    } else {
      out.add(part);
    }
  }
  final joined = out.join('/');
  return isAbs ? '/$joined' : joined;
}

/// Run the CLI; returns the process exit code.
int run(List<String> argv) {
  final args = List<String>.of(argv);

  // Global -C/--root acts as a fallback default; a subcommand-level
  // -C/--root takes precedence.
  String? globalRoot;
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '-C' || args[i] == '--root') && i + 1 < args.length) {
      globalRoot = args[i + 1];
      args.removeRange(i, i + 2);
      i--;
    }
  }
  _root = globalRoot;

  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    out(rootHelp);
    return args.isEmpty ? 2 : 0;
  }

  if (args.first == '-V' || args.first == '--version') {
    out('$version\n');
    return 0;
  }

  final command = args.first;
  final rest = args.sublist(1);
  try {
    return switch (command) {
      'scan' => _runScan(rest),
      'init' => _runInit(rest),
      'fix' => _runFix(rest),
      'diff' => _runDiff(rest),
      'snapshot' => _runSnapshot(rest),
      'snapshot-diff' => _runSnapshotDiff(rest),
      'sync' => _runSync(rest),
      'generate' => _runGenerate(rest),
      'help' => _runHelp(rest),
      _ => _unknownCommand(command),
    };
  } on UsageException catch (e) {
    err('error: ${e.message}\n\nUsage: ${e.usage}\n\nFor more information, try \'--help\'.\n');
    return e.exitCode;
  }
}

int _unknownCommand(String name) {
  err("error: unknown command '$name'\n");
  return 2;
}

int _runHelp(List<String> args) {
  // `envdoctor help [command]` — print the root help or a subcommand's help.
  if (args.isEmpty) {
    out(rootHelp);
    return 0;
  }
  out(rootHelp);
  return 0;
}

int _runScan(List<String> argv) {
  const usage = 'envdoctor scan [OPTIONS]';
  String? root;
  var strict = false;
  var format = OutputFormat.human;
  var json = false;
  var verbose = false;
  final only = <String>[];
  String? baseline;
  String? writeBaseline;
  var staged = false;
  String? since;
  final cur = ArgCursor(argv, usage);
  String? arg;
  while ((arg = cur.next()) != null) {
    switch (arg) {
      case '-C' || '--root':
        root = cur.requireValue(arg!);
      case '-d' || '--dir':
        root = cur.requireValue(arg!);
      case '--strict':
        strict = true;
      case '--format':
        final value = cur.requireValue(arg!);
        format = switch (value) {
          'human' => OutputFormat.human,
          'json' => OutputFormat.json,
          'sarif' => OutputFormat.sarif,
          _ => throw UsageException(
              'invalid value \'$value\' for \'--format <FORMAT>\' [possible values: human, json, sarif]',
              usage),
        };
      case '--json':
        json = true;
      case '-v' || '--verbose':
        verbose = true;
      case '--only':
        only.addAll(parseRules(cur.requireValue(arg!)));
      case '--baseline':
        baseline = cur.requireValue(arg!);
      case '--write-baseline':
        writeBaseline = cur.requireValue(arg!);
      case '--staged':
        staged = true;
      case '--since':
        since = cur.requireValue(arg!);
      case '-h' || '--help':
        out(scanHelp);
        return 0;
      default:
        throw cur.unexpected(arg!);
    }
  }
  final resolvedRoot = resolveRoot(root ?? _root);
  if (json) format = OutputFormat.json;
  return runScan(ScanOptions(
    rootDir: resolvedRoot,
    strict: strict,
    format: format,
    verbose: verbose,
    only: only,
    baseline: baseline,
    writeBaseline: writeBaseline,
    staged: staged,
    since: since,
  ));
}

int _runInit(List<String> argv) {
  const usage = 'envdoctor init [OPTIONS]';
  String? root;
  var force = false;
  final cur = ArgCursor(argv, usage);
  String? arg;
  while ((arg = cur.next()) != null) {
    switch (arg) {
      case '-C' || '--root':
        root = cur.requireValue(arg!);
      case '-d' || '--dir':
        root = cur.requireValue(arg!);
      case '--force':
        force = true;
      case '-h' || '--help':
        out(initHelp);
        return 0;
      default:
        throw cur.unexpected(arg!);
    }
  }
  return runInit(InitOptions(rootDir: resolveRoot(root ?? _root), force: force));
}

int _runFix(List<String> argv) {
  const usage = 'envdoctor fix [OPTIONS]';
  String? root;
  var dryRun = false;
  var force = false;
  var verbose = false;
  final cur = ArgCursor(argv, usage);
  String? arg;
  while ((arg = cur.next()) != null) {
    switch (arg) {
      case '-C' || '--root':
        root = cur.requireValue(arg!);
      case '-d' || '--dir':
        root = cur.requireValue(arg!);
      case '--dry-run':
        dryRun = true;
      case '--force':
        force = true;
      case '-v' || '--verbose':
        verbose = true;
      case '-h' || '--help':
        out(fixHelp);
        return 0;
      default:
        throw cur.unexpected(arg!);
    }
  }
  return runFix(FixOptions(
    rootDir: resolveRoot(root ?? _root),
    dryRun: dryRun,
    force: force,
    verbose: verbose,
  ));
}

int _runDiff(List<String> argv) {
  const usage = 'envdoctor diff [OPTIONS] <ENV_A> <ENV_B>';
  String? root;
  var json = false;
  final cur = ArgCursor(argv, usage);
  while (true) {
    final arg = cur.next();
    if (arg == null) break;
    if (arg == '-C' || arg == '--root') {
      root = cur.requireValue(arg);
    } else if (arg == '-d' || arg == '--dir') {
      root = cur.requireValue(arg);
    } else if (arg == '--json') {
      json = true;
    } else if (arg == '-h' || arg == '--help') {
      out(diffHelp);
      return 0;
    } else if (arg.startsWith('-')) {
      throw cur.unexpected(arg);
    } else {
      cur.positionals.add(arg);
    }
  }
  if (cur.positionals.isEmpty) {
    err("error: missing required argument 'environment1'\n");
    return 1;
  }
  if (cur.positionals.length == 1) {
    err("error: missing required argument 'environment2'\n");
    return 1;
  }
  return runDiff(DiffOptions(
    rootDir: resolveRoot(root ?? _root),
    envA: cur.positionals[0],
    envB: cur.positionals[1],
    json: json,
  ));
}

int _runSync(List<String> argv) {
  const usage = 'envdoctor sync [OPTIONS] <FROM> <TO>';
  String? root;
  var dryRun = false;
  final cur = ArgCursor(argv, usage);
  while (true) {
    final arg = cur.next();
    if (arg == null) break;
    if (arg == '-C' || arg == '--root') {
      root = cur.requireValue(arg);
    } else if (arg == '-d' || arg == '--dir') {
      root = cur.requireValue(arg);
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '-h' || arg == '--help') {
      out(syncHelp);
      return 0;
    } else if (arg.startsWith('-')) {
      throw cur.unexpected(arg);
    } else {
      cur.positionals.add(arg);
    }
  }
  if (cur.positionals.isEmpty) {
    err("error: missing required argument 'from'\n");
    return 1;
  }
  if (cur.positionals.length == 1) {
    err("error: missing required argument 'to'\n");
    return 1;
  }
  return runSync(SyncOptions(
    rootDir: resolveRoot(root ?? _root),
    envA: cur.positionals[0],
    envB: cur.positionals[1],
    dryRun: dryRun,
  ));
}

int _runSnapshot(List<String> argv) {
  const usage = 'envdoctor snapshot [OPTIONS]';
  String? root;
  String? output;
  var token = false;
  var json = false;
  var globals = false;
  final cur = ArgCursor(argv, usage);
  String? arg;
  while ((arg = cur.next()) != null) {
    switch (arg) {
      case '-C' || '--root':
        root = cur.requireValue(arg!);
      case '-d' || '--dir':
        root = cur.requireValue(arg!);
      case '-o' || '--output':
        output = cur.requireValue(arg!);
      case '--token':
        token = true;
      case '--json':
        json = true;
      case '--globals':
        globals = true;
      case '-h' || '--help':
        out(snapshotHelp);
        return 0;
      default:
        throw cur.unexpected(arg!);
    }
  }
  return runSnapshot(SnapshotOptions(
    rootDir: resolveRoot(root ?? _root),
    output: output,
    token: token,
    json: json,
    globals: globals,
  ));
}

int _runSnapshotDiff(List<String> argv) {
  const usage = 'envdoctor snapshot-diff [OPTIONS] <A> <B>';
  String? root;
  var json = false;
  final cur = ArgCursor(argv, usage);
  while (true) {
    final arg = cur.next();
    if (arg == null) break;
    if (arg == '-C' || arg == '--root') {
      root = cur.requireValue(arg);
    } else if (arg == '-d' || arg == '--dir') {
      root = cur.requireValue(arg);
    } else if (arg == '--json') {
      json = true;
    } else if (arg == '-h' || arg == '--help') {
      out(snapshotDiffHelp);
      return 0;
    } else if (arg.startsWith('-')) {
      throw cur.unexpected(arg);
    } else {
      cur.positionals.add(arg);
    }
  }
  if (cur.positionals.isEmpty) {
    err("error: missing required argument 'a'\n");
    return 1;
  }
  if (cur.positionals.length == 1) {
    err("error: missing required argument 'b'\n");
    return 1;
  }
  return runSnapshotDiff(SnapshotDiffOptions(
    rootDir: resolveRoot(root ?? _root),
    a: cur.positionals[0],
    b: cur.positionals[1],
    json: json,
  ));
}

int _runGenerate(List<String> argv) {
  const usage = 'envdoctor generate [OPTIONS] <COMMAND>';
  String? root;
  String? output;
  String? target;
  final cur = ArgCursor(argv, usage);
  while (true) {
    final arg = cur.next();
    if (arg == null) break;
    if (arg == '-C' || arg == '--root') {
      root = cur.requireValue(arg);
    } else if (arg == '-o' || arg == '--output') {
      output = cur.requireValue(arg);
    } else if (arg == '-h' || arg == '--help') {
      out(generateHelp);
      return 0;
    } else if (arg.startsWith('-')) {
      throw cur.unexpected(arg);
    } else {
      if (target != null) throw cur.unexpected(arg);
      target = arg;
    }
  }

  final GenerateTarget parsedTarget;
  switch (target) {
    case 'env-example':
      parsedTarget = GenerateTarget.envExample;
    case 'env-doc':
      parsedTarget = GenerateTarget.envDoc;
    case 'env-types':
      parsedTarget = GenerateTarget.envTypes;
    case 'config-schema':
      parsedTarget = GenerateTarget.configSchema;
    case 'config-template':
      parsedTarget = GenerateTarget.configTemplate;
    case 'github-actions':
      parsedTarget = GenerateTarget.githubActions;
    case null:
      throw UsageException(
          'the following required arguments were not provided:\n  <COMMAND>',
          usage);
    default:
      throw UsageException("unrecognized subcommand '$target'", usage);
  }
  return runGenerate(GenerateOptions(
    target: parsedTarget,
    rootDir: resolveRoot(root ?? _root),
    output: output,
  ));
}

const String scanHelp = '''
Scan for environment variable issues

Usage: envdoctor scan [OPTIONS]

Options:
      --format <FORMAT>
          Output format [default: human] [possible values: human, json, sarif]
      --strict
          Fail on warnings (strict mode)
  -C, --root <ROOT>
          Project root (default: current directory)
  -d, --dir <DIR>
          Project directory (default: current directory)
  -v, --verbose
          Show file:line locations in the report
      --only <ONLY>
          Restrict the audit to these detector ids (comma-separated)
      --baseline <BASELINE>
          Suppress findings listed in a baseline file
      --write-baseline <WRITE_BASELINE>
          Write the current findings to a baseline file
      --staged
          Only scan files with staged git changes
      --since <SINCE>
          Only scan files changed since a git ref
      --json
          Alias for --format json
  -h, --help
          Print help
''';

const String initHelp = '''
Initialize a new envdoctor config

Usage: envdoctor init [OPTIONS]

Options:
  -C, --root <ROOT>  Project root (default: current directory)
      --force        Force overwrite existing config
  -h, --help         Print help
''';

const String fixHelp = '''
Auto-fix certain issues

Usage: envdoctor fix [OPTIONS]

Options:
  -C, --root <ROOT>  Project root (default: current directory)
      --dry-run      Preview changes without writing any files
      --force        Overwrite files that already exist (default: skip them)
  -h, --help         Print help
''';

const String diffHelp = '''
Show differences between environments

Usage: envdoctor diff [OPTIONS] <ENV_A> <ENV_B>

Arguments:
  <ENV_A>  First environment (e.g. development, production, or dev/prod aliases)
  <ENV_B>  Second environment

Options:
  -C, --root <ROOT>  Project root (default: current directory)
      --json         Print the diff as JSON
  -h, --help         Print help
''';

const String syncHelp = '''
Copy missing keys from one environment file to another

Usage: envdoctor sync [OPTIONS] <FROM> <TO>

Arguments:
  <FROM>  Source environment (e.g. development, production, or dev/prod aliases)
  <TO>    Target environment to receive the missing keys

Options:
  -C, --root <ROOT>  Project root (default: current directory)
      --dry-run      Preview the changes without writing
  -h, --help         Print help
''';

const String snapshotHelp = '''
Capture runtime snapshot

Usage: envdoctor snapshot [OPTIONS]

Options:
  -C, --root <ROOT>      Project root (default: current directory)
  -o, --output <OUTPUT>  Write the snapshot JSON to a file
      --token            Print a compact, paste-safe token instead of a human summary
      --json             Print the raw snapshot JSON
      --globals          Include the (slow) global package inventory
  -h, --help             Print help
''';

const String snapshotDiffHelp = '''
Compare two runtime snapshots (tokens or JSON files)

Usage: envdoctor snapshot-diff [OPTIONS] <A> <B>

Arguments:
  <A>  First snapshot — a token (`envd1:…`) or a path to a snapshot JSON file
  <B>  Second snapshot — a token (`envd1:…`) or a path to a snapshot JSON file

Options:
  -C, --root <ROOT>  Project root (default: current directory)
      --json         Print the diff as JSON
  -h, --help         Print help
''';

const String generateHelp = '''
Generate files from model

Usage: envdoctor generate [OPTIONS] <COMMAND>

Commands:
  env-example      Generate .env.example
  env-doc          Generate ENVIRONMENT.md documentation
  env-types        Generate TypeScript types (env.d.ts)
  config-schema    Generate JSON schema for configuration
  config-template  Generate TOML config template
  github-actions   Generate GitHub Actions workflow snippet

Options:
  -C, --root <ROOT>      Project root (default: current directory)
  -o, --output <OUTPUT>  Output file (default: stdout)
  -h, --help             Print help
''';
