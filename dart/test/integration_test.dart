/// Integration tests mirroring the .NET port's test suite, adapted to the
/// TypeScript reference behavior the Dart port follows (e.g. `init` writes
/// `envdoctor.config.mjs`, `generate` prints to stdout unless `--output`).
library;

import 'dart:io';

import 'package:envdoctor/src/commands/diff.dart';
import 'package:envdoctor/src/commands/generate.dart';
import 'package:envdoctor/src/commands/init.dart';
import 'package:envdoctor/src/commands/scan.dart';
import 'package:envdoctor/src/commands/snapshot_diff.dart';
import 'package:envdoctor/src/commands/sync.dart';
import 'package:envdoctor/src/models/environment_variable.dart';
import 'package:envdoctor/src/models/runtime_snapshot.dart';
import 'package:envdoctor/src/models/variable_type.dart';
import 'package:envdoctor/src/runtime/capture.dart';
import 'package:envdoctor/src/runtime/token.dart';
import 'package:envdoctor/src/utils/glob.dart';
import 'package:envdoctor/src/utils/type_infer.dart';
import 'package:test/test.dart';

class TempProject {
  final String path =
      '${Directory.systemTemp.path}/envdoctor-test-${DateTime.now().microsecondsSinceEpoch}-${Directory.systemTemp.listSync().length}';

  TempProject() {
    Directory(path).createSync(recursive: true);
  }

  void write(String rel, String content) {
    final full = '$path/$rel';
    Directory(full.substring(0, full.lastIndexOf('/'))).createSync(recursive: true);
    File(full).writeAsStringSync(content);
  }

  String read(String rel) => File('$path/$rel').readAsStringSync();

  bool exists(String rel) => File('$path/$rel').existsSync();

  void dispose() {
    try {
      Directory(path).deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

void createTestProject(TempProject dir) {
  dir.write('.env',
      'DATABASE_URL=postgres://localhost:5432/myapp\nAPI_KEY=secret123\nDEBUG=true\nPORT=3000\n');
  dir.write('.env.example', 'DATABASE_URL=\nAPI_KEY=\nDEBUG=false\nPORT=\n');
  dir.write('config.js',
      'const db = process.env.DATABASE_URL;\nconst port = process.env.PORT;\nconst missing = process.env.MISSING_SECRET;\n');
  dir.write('docker-compose.yml',
      "version: '3'\nservices:\n  app:\n    environment:\n      - DATABASE_URL\n      - API_KEY\n      - DEBUG\n");
}

ScanOptions scan(TempProject dir, {OutputFormat format = OutputFormat.human}) =>
    ScanOptions(rootDir: dir.path, format: format);

void main() {
  test('scan finds issues', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);
    expect(runScan(scan(temp)), 1);
  });

  test('init creates config', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    final exit = runInit(InitOptions(rootDir: temp.path, force: true));
    expect(exit, 0);
    expect(temp.exists('envdoctor.config.mjs'), isTrue);
    final content = temp.read('envdoctor.config.mjs');
    expect(content, contains('ignoreVariables'));
  });

  test('generate env-example', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);
    final exit = runGenerate(GenerateOptions(
        target: GenerateTarget.envExample, rootDir: temp.path, output: '.env.example'));
    expect(exit, 0);
    final content = temp.read('.env.example');
    expect(content, contains('DATABASE_URL'));
    expect(content, contains('API_KEY'));
  });

  test('generate env-doc', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);
    expect(
        runGenerate(GenerateOptions(
            target: GenerateTarget.envDoc, rootDir: temp.path, output: 'ENVIRONMENT.md')),
        0);
    expect(temp.exists('ENVIRONMENT.md'), isTrue);
  });

  test('generate env-types', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);
    expect(
        runGenerate(GenerateOptions(
            target: GenerateTarget.envTypes, rootDir: temp.path, output: 'env.d.ts')),
        0);
  });

  test('generate config-schema', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    expect(
        runGenerate(GenerateOptions(
            target: GenerateTarget.configSchema, rootDir: temp.path, output: 'schema.json')),
        0);
    expect(temp.read('schema.json'), contains('"variableSchema"'));
  });

  test('generate config-template', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    expect(
        runGenerate(GenerateOptions(
            target: GenerateTarget.configTemplate,
            rootDir: temp.path,
            output: 'envdoctor.config.toml')),
        0);
    expect(temp.read('envdoctor.config.toml'), contains('envFilePatterns'));
  });

  test('generate github-actions', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);
    expect(
        runGenerate(GenerateOptions(
            target: GenerateTarget.githubActions,
            rootDir: temp.path,
            output: 'envdoctor.yml')),
        0);
  });

  test('scan json output', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);
    expect(runScan(scan(temp, format: OutputFormat.json)), 1);
  });

  test('scan sarif output', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);
    expect(runScan(scan(temp, format: OutputFormat.sarif)), 1);
  });

  test('scan with config', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    createTestProject(temp);

    expect(runScan(scan(temp)), 1);

    temp.write('envdoctor.config.toml', 'ignoreVariables = ["MISSING_SECRET"]\n');
    expect(runScan(scan(temp)), 0);
  });

  test('diff reports missing keys', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    temp.write('.env', 'DATABASE_URL=postgres://localhost/dev\nDEBUG=true\n');
    temp.write('.env.production', 'DATABASE_URL=postgres://prod/db\n');

    expect(
        runDiff(DiffOptions(
            rootDir: temp.path, envA: 'development', envB: 'production')),
        1);
    expect(
        runDiff(DiffOptions(
            rootDir: temp.path, envA: 'development', envB: 'production', json: true)),
        1);
  });

  test('sync dry-run does not modify target', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    temp.write('.env', 'DATABASE_URL=postgres://localhost/dev\nDEBUG=true\nEXTRA_KEY=value\n');
    temp.write('.env.production', 'DATABASE_URL=postgres://prod/db\n');
    final before = temp.read('.env.production');

    final exit = runSync(SyncOptions(
        rootDir: temp.path, envA: 'development', envB: 'production', dryRun: true));
    expect(exit, 0);
    expect(temp.read('.env.production'), before);
  });

  test('snapshot-diff identical and differing', () {
    final temp = TempProject();
    addTearDown(temp.dispose);
    final snapshot = captureSnapshot();
    final json = snapshotToJson(snapshot);

    temp.write('a.json', json);
    temp.write('b.json', json);

    expect(
        runSnapshotDiff(SnapshotDiffOptions(
            rootDir: temp.path, a: 'a.json', b: 'b.json')),
        0);

    snapshot.tools.add(ToolInfo(tool: 'zzz-fake-tool', version: '9.9.9', resolvedFrom: 'PATH'));
    temp.write('b.json', snapshotToJson(snapshot));

    expect(
        runSnapshotDiff(SnapshotDiffOptions(
            rootDir: temp.path, a: 'a.json', b: 'b.json', json: true)),
        1);
  });

  test('glob matching', () {
    expect(matchesGlob('AWS_*', 'AWS_SECRET'), isTrue);
    expect(matchesGlob('AWS_*', 'GCP_SECRET'), isFalse);
    expect(matchesGlob('FOO*', 'FOO'), isTrue);
    expect(matchesGlob('FOO*', 'FOOBAR'), isTrue);
    expect(matchesGlob('FOO*', 'BAR'), isFalse);

    expect(matchesAnyGlob(['AWS_*', 'GCP_*'], 'AWS_KEY'), isTrue);
    expect(matchesAnyGlob(['AWS_*', 'GCP_*'], 'GCP_KEY'), isTrue);
    expect(matchesAnyGlob(['AWS_*', 'GCP_*'], 'AZURE_KEY'), isFalse);
  });

  test('variable type inference', () {
    expect(inferType('42'), VariableType.integer);
    expect(inferType('3.14'), VariableType.float);
    expect(inferType('true'), VariableType.boolean);
    expect(inferType('false'), VariableType.boolean);
    expect(inferType('https://example.com'), VariableType.url);
    expect(inferType('http://localhost:3000'), VariableType.url);
    expect(inferType('{"key": "value"}'), VariableType.json);
    expect(inferType('hello'), VariableType.string);
    expect(inferType(null), VariableType.unknown);
  });

  test('secret detection', () {
    expect(EnvironmentVariable.isSecretName('API_KEY'), isTrue);
    expect(EnvironmentVariable.isSecretName('SECRET'), isTrue);
    expect(EnvironmentVariable.isSecretName('PASSWORD'), isTrue);
    expect(EnvironmentVariable.isSecretName('TOKEN'), isTrue);
    expect(EnvironmentVariable.isSecretName('PRIVATE_KEY'), isTrue);
    expect(EnvironmentVariable.isSecretName('DEBUG'), isFalse);
    expect(EnvironmentVariable.isSecretName('PORT'), isFalse);
    expect(EnvironmentVariable.isSecretName('NODE_ENV'), isFalse);
  });
}
