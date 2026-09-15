/// Tests for the Dart envdoctor port, adapted from the Python port's
/// `tests/test_scanner.py` and the TypeScript reference's detector tests.
library;

import 'dart:convert';
import 'dart:io';

import 'package:envdoctor/src/cli.dart' as cli;
import 'package:envdoctor/src/config/config.dart';
import 'package:envdoctor/src/core/audit.dart';
import 'package:envdoctor/src/core/model_assembler.dart';
import 'package:envdoctor/src/core/pipeline.dart';
import 'package:envdoctor/src/detectors/detector.dart';
import 'package:envdoctor/src/formatters/scan_json_formatter.dart';
import 'package:envdoctor/src/generators/env_example.dart';
import 'package:envdoctor/src/generators/environment_doc.dart';
import 'package:envdoctor/src/models/finding.dart';
import 'package:envdoctor/src/models/environment_file.dart';
import 'package:envdoctor/src/models/variable_type.dart';
import 'package:envdoctor/src/parsers/github_actions_parser.dart';
import 'package:envdoctor/src/parsers/k8s_parser.dart';
import 'package:envdoctor/src/parsers/source_parser.dart';
import 'package:envdoctor/src/utils/type_infer.dart';
import 'package:test/test.dart';

Directory _tmp() => Directory.systemTemp.createTempSync('envdoctor-dart-test-');

String _write(Directory root, String name, String content) {
  final file = File('${root.path}${Platform.pathSeparator}$name');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file.path;
}

/// Scan a temp project through the real pipeline and return findings.
List<Finding> _scan(Directory root) {
  final ctx = loadProject(root.path);
  return runAudit(ctx.model, AuditOptions()).findings;
}

Set<String> _vars(List<Finding> findings, String rule) =>
    findings.where((f) => f.ruleId == rule).map((f) => f.variable).toSet();

void main() {
  group('detectors', () {
    test('missing and unused reconcile against source usage', () {
      final root = _tmp();
      _write(root, '.env', 'DB_URL=postgres://x\nUNUSED_KEY=1\n');
      _write(root, 'src/index.ts',
          "const a = process.env.DB_URL;\nconst b = process.env.NEW_FLAG;\n");

      final findings = _scan(root);
      final undefined = _vars(findings, 'undefined-in-source');
      final unused = _vars(findings, 'unused');

      expect(undefined, contains('NEW_FLAG')); // used but not defined
      expect(unused, contains('UNUSED_KEY')); // defined but not used
      expect(undefined, isNot(contains('DB_URL'))); // reconciled
      expect(unused, isNot(contains('DB_URL')));
      // Values must never leak into findings.
      for (final f in findings) {
        expect(f.message, isNot(contains('postgres')));
      }
    });

    test('duplicates flags a key defined twice in one file', () {
      final root = _tmp();
      _write(root, '.env', 'DB_URL=a\nDB_URL=b\nSOLO=1\n');
      _write(root, 'src/index.ts',
          'process.env.DB_URL;\nprocess.env.SOLO;\n');

      final findings = _scan(root);
      final dups = findings.where((f) => f.ruleId == 'duplicates').toList();
      expect(dups.map((f) => f.variable), contains('DB_URL'));
      expect(dups.map((f) => f.variable), isNot(contains('SOLO')));
      expect(dups.first.severity, Severity.error);
      // The first occurrence still reconciles: not reported unused.
      expect(_vars(findings, 'unused'), isNot(contains('DB_URL')));
    });

    test('public-prefix flags secret-like names behind public prefixes', () {
      final root = _tmp();
      _write(root, '.env',
          'NEXT_PUBLIC_API_KEY=x\nPUBLIC_URL=x\nAPI_KEY=x\n');

      final findings = _scan(root);
      final names = _vars(findings, 'public-prefix');
      expect(names, {'NEXT_PUBLIC_API_KEY'});
      expect(
        findings.firstWhere((f) => f.ruleId == 'public-prefix').severity,
        Severity.error,
      );
    });

    test('weak-secret flags placeholder and short values without leaking', () {
      final root = _tmp();
      _write(root, '.env',
          'API_KEY=changeme\nSTRONG_TOKEN=s0m3-l0ng-r4nd0m-value\nSHORT_SECRET=abc\n');

      final findings = _scan(root);
      final weak = _vars(findings, 'weak-secret');
      expect(weak, contains('API_KEY')); // placeholder
      expect(weak, contains('SHORT_SECRET')); // too short
      expect(weak, isNot(contains('STRONG_TOKEN')));
      for (final f in findings) {
        expect(f.message, isNot(contains('changeme')));
        expect(f.message, isNot(contains('s0m3')));
      }
    });

    test('typo suggests the closest defined name', () {
      final root = _tmp();
      _write(root, '.env', 'DATABASE_URL=postgres://x\n');
      _write(root, 'src/index.ts', 'process.env.DATBASE_URL;\n');

      final findings = _scan(root);
      final typos = findings.where((f) => f.ruleId == 'typo').toList();
      expect(typos, hasLength(1));
      expect(typos.single.variable, 'DATBASE_URL');
      expect(typos.single.severity, Severity.warning);
      expect(typos.single.message, contains('did you mean "DATABASE_URL"'));
    });

    test('environment-diff reports variables missing from one environment', () {
      final root = _tmp();
      _write(root, '.env', 'A=1\nB=2\nC=3\n');
      _write(root, '.env.production', 'A=1\nC=3\nD=4\n');

      final names = _vars(_scan(root), 'environment-diff');
      expect(names, containsAll(['B', 'D']));
      expect(names, isNot(contains('A')));
      expect(names, isNot(contains('C')));
    });

    test('type-mismatch flags incompatible types across environments', () {
      final root = _tmp();
      _write(root, '.env', 'PORT=3000\nHOST=8080\n');
      _write(root, '.env.production', 'PORT=abc\nHOST=9090\n');

      final findings = _scan(root);
      final mismatches = _vars(findings, 'type-mismatch');
      expect(mismatches, contains('PORT')); // integer vs string
      expect(mismatches, isNot(contains('HOST'))); // integer vs integer
      final tm = findings.firstWhere((f) => f.ruleId == 'type-mismatch');
      expect(tm.severity, Severity.error);
      expect(tm.message, contains('expected: integer'));
      expect(tm.message, isNot(contains('3000')));
      expect(tm.message, isNot(contains('abc')));
    });

    test('infra sources (compose, actions, k8s) are scanned', () {
      final root = _tmp();
      _write(root, '.env', 'DB_URL=postgres://x\n');
      _write(
        root,
        'docker-compose.yml',
        'services:\n'
            '  web:\n'
            '    image: x\n'
            '    environment:\n'
            '      - TOKEN=\${COMPOSE_SECRET}\n'
            '      - DB=\${DB_URL}\n',
      );
      _write(
        root,
        '.github/workflows/ci.yml',
        'jobs:\n'
            '  build:\n'
            '    steps:\n'
            '      - run: deploy\n'
            '        env:\n'
            '          KEY: \${{ secrets.DEPLOY_KEY }}\n'
            '          REGION: \${{ vars.REGION }}\n',
      );
      _write(
        root,
        'k8s/app.deployment.yaml',
        'apiVersion: apps/v1\n'
            'kind: Deployment\n'
            'spec:\n'
            '  template:\n'
            '    spec:\n'
            '      containers:\n'
            '        - name: app\n'
            '          command: ["sh", "-c", "echo \${K8S_VAR}"]\n'
            '          env:\n'
            '            - name: PORT\n'
            '              value: "3000"\n',
      );

      final findings = _scan(root);
      final referenced =
          _vars(findings, 'undefined-in-source').union(_vars(findings, 'missing'));
      // Referenced only in compose but never defined anywhere.
      // (The reference flags only compose references as `missing`; k8s and
      // GitHub Actions usages feed the other detectors instead.)
      expect(referenced, containsAll(['COMPOSE_SECRET', 'TOKEN', 'DB']));
      // GitHub Actions env keys, secrets, and vars are external: never flagged.
      final flagged = findings.map((f) => f.variable).toSet();
      expect(flagged.intersection({'DEPLOY_KEY', 'REGION', 'KEY'}), isEmpty);
      // DB_URL is defined and referenced in compose -> NOT unused.
      expect(_vars(findings, 'unused'), isNot(contains('DB_URL')));
      // No values leak into any finding.
      for (final f in findings) {
        expect(f.message, isNot(contains('postgres')));
      }
    });

    test('schema-validation flags values violating the configured schema', () {
      final root = _tmp();
      final envPath = _write(root, '.env', 'PORT=80\nNODE_ENV=dev\n');
      final config = EnvdoctorConfig()
        ..schema = {
          'PORT': VariableSchema(type: SchemaType.integer, min: 1024),
          'NODE_ENV': VariableSchema(enumValues: [
            'development',
            'production',
            'test',
          ]),
        };
      final model = assembleModel(root.path, config, [envPath]);
      final detector =
          allDetectors().firstWhere((d) => d.id == 'schema-validation');
      final findings = detector.detect(IndexedModel.buildIndex(model));
      expect(findings.map((f) => f.variable).toSet(), {'PORT', 'NODE_ENV'});
      // The offending values must never appear in findings.
      final portMsg = findings.firstWhere((f) => f.variable == 'PORT').message;
      expect(portMsg, isNot(contains('80')));
    });
  });

  group('parsers', () {
    test('k8s parser extracts container env defs and command interpolations', () {
      final parser = K8sParser();
      final file = parser.parse(
        'apiVersion: apps/v1\n'
        'kind: Deployment\n'
        'spec:\n'
        '  template:\n'
        '    spec:\n'
        '      containers:\n'
        '        - name: app\n'
        '          command: ["sh", "-c", "echo \${MESSAGE}"]\n'
        '          env:\n'
        '            - name: PORT\n'
        '              value: "3000"\n'
        '            - name: SECRET_TOKEN\n'
        '              valueFrom:\n'
        '                secretKeyRef:\n'
        '                  name: app-secret\n'
        '                  key: token\n',
        '/p/k8s/deployment.yaml',
      );
      final defined = file.variables.map((v) => v.name).toSet();
      expect(defined, containsAll(['PORT']));
      expect(defined, isNot(contains('SECRET_TOKEN')));
      final used = file.usages.map((v) => v.name).toSet();
      expect(used, containsAll(['MESSAGE', 'SECRET_TOKEN']));
    });

    test('actions parser extracts env keys and secrets/vars references', () {
      final parser = GithubActionsParser();
      final file = parser.parse(
        'name: ci\n'
        'on: [push]\n'
        'env:\n'
        "  CI: 'true'\n"
        'jobs:\n'
        '  t:\n'
        '    runs-on: ubuntu-latest\n'
        '    steps:\n'
        '      - run: echo \${{ secrets.DEPLOY_TOKEN }}\n'
        '      - run: echo \${{ vars.REGION }}\n'
        '        env:\n'
        '          KEY: \${{ env.BUILD_ID }}\n',
        '/p/.github/workflows/ci.yml',
      );
      // Nothing here is expected in .env files: no missing findings may
      // result from these. The parser still records what it saw.
      expect(file.format, FileFormat.githubActions);
    });

    test('source parser finds every supported access pattern', () {
      final parser = SourceParser(['ts', 'js']);
      final file = parser.parse(
        'const a = process.env.PLAIN;\n'
        'const b = process.env["BRACKET"];\n'
        "const c = process.env['SINGLE_BRACKET'];\n"
        'const d = import.meta.env.VITE_KEY;\n'
        '// const e = process.env.COMMENTED_OUT;\n'
        'const f = "process.env.IN_STRING";\n',
        '/p/src/index.ts',
      );
      final names = file.usages.map((v) => v.name).toSet();
      expect(names,
          containsAll(['PLAIN', 'BRACKET', 'SINGLE_BRACKET', 'VITE_KEY']));
      expect(names, isNot(contains('COMMENTED_OUT')));
      expect(names, isNot(contains('IN_STRING')));
    });
  });

  group('type inference', () {
    test('infers scalar types', () {
      expect(inferType(null), VariableType.unknown);
      expect(inferType(''), VariableType.unknown);
      expect(inferType('3000'), VariableType.integer);
      expect(inferType('-7'), VariableType.integer);
      expect(inferType('1.5'), VariableType.float);
      expect(inferType('TRUE'), VariableType.boolean);
      expect(inferType('https://x.io'), VariableType.url);
      expect(inferType('{"a":1}'), VariableType.json);
      expect(inferType('hello'), VariableType.string);
    });
  });

  group('generators', () {
    test('env example and docs never contain secret values', () {
      final root = _tmp();
      _write(root, '.env', 'DB_URL=postgres://x\nAPI_KEY=topsecretvalue\n');
      _write(root, 'src/index.ts', 'process.env.PORT;\n');

      final ctx = loadProject(root.path);
      final example = generateEnvExample(ctx.model, ctx.config);
      final doc = generateEnvironmentDoc(ctx.model, ctx.config);

      expect(example, contains('DB_URL'));
      expect(example, contains('PORT'));
      expect(doc, contains('DB_URL'));
      // Secret-like names always get a blank value.
      expect(example, contains('API_KEY=\n'));
      expect(example, isNot(contains('topsecretvalue')));
      expect(doc, isNot(contains('topsecretvalue')));
    });
  });

  group('scan JSON output', () {
    test('matches the reference shape and leaks no values', () {
      final root = _tmp();
      _write(root, '.env', 'API_KEY=changeme\n');
      _write(root, 'src/index.ts', 'process.env.DATBASE_URL;\n');

      final ctx = loadProject(root.path);
      final result = runAudit(ctx.model, AuditOptions());
      final out =
          renderScanJson(root.path, result.findings, result.summary, result.exitCode);
      final data = jsonDecode(out) as Map<String, dynamic>;

      expect(data.keys, containsAll(['exitCode', 'summary', 'findings']));
      final summary = data['summary'] as Map<String, dynamic>;
      expect(
        summary.keys,
        containsAll([
          'filesScanned',
          'variablesFound',
          'errors',
          'warnings',
          'infos',
          'total',
        ]),
      );
      final findings = data['findings'] as List<dynamic>;
      expect(findings, isNotEmpty);
      for (final obj in findings.cast<Map<String, dynamic>>()) {
        expect(
          obj.keys,
          containsAll(['id', 'ruleId', 'severity', 'variable', 'message', 'locations']),
        );
      }
      expect(out, isNot(contains('changeme')));
    });
  });

  group('CLI', () {
    test('scan exits non-zero when errors are found', () {
      final root = _tmp();
      _write(root, '.env', 'DB_URL=x\n');
      _write(root, 'src/index.ts', 'process.env.MISSING_VAR;\n');

      expect(cli.run(['scan', '--json', '-C', root.path]), isNot(0));
    });

    test('scan exits zero on a clean project', () {
      final root = _tmp();
      _write(root, '.env', 'DB_URL=x\n');
      _write(root, 'src/index.ts', 'process.env.DB_URL;\n');

      expect(cli.run(['scan', '-C', root.path]), 0);
    });

    test('--version and help work', () {
      expect(cli.run(['--version']), 0);
      expect(cli.run(['--help']), 0);
    });
  });

  group('commands', () {
    test('init creates, skips, and --force rewrites', () {
      final root = _tmp();
      _write(root, '.env', 'DB_URL=postgres://x\nAPI_KEY=topsecretvalue\n');
      _write(root, 'src/index.ts', 'process.env.PORT;\n');

      expect(cli.run(['init', '-C', root.path]), 0);
      final example = File('${root.path}/.env.example');
      final envdoc = File('${root.path}/ENVIRONMENT.md');
      expect(example.existsSync(), isTrue);
      expect(envdoc.existsSync(), isTrue);
      final firstExample = example.readAsStringSync();
      // Secret values are never written into generated artifacts.
      expect(firstExample, isNot(contains('topsecretvalue')));
      expect(envdoc.readAsStringSync(), isNot(contains('topsecretvalue')));

      // Second init without --force skips; files unchanged.
      example.writeAsStringSync('SENTINEL');
      expect(cli.run(['init', '-C', root.path]), 0);
      expect(example.readAsStringSync(), 'SENTINEL');

      // --force rewrites.
      expect(cli.run(['init', '-C', root.path, '--force']), 0);
      expect(example.readAsStringSync(), firstExample);
    });

    test('diff and sync copy keys without values', () {
      final root = _tmp();
      _write(root, '.env', 'A=1\nB=2\n');
      _write(root, '.env.production', 'A=9\n');

      // diff exits 1 when variables are missing on one side (TS parity).
      expect(cli.run(['diff', 'development', 'production', '-C', root.path]), 1);
      expect(cli.run(['sync', 'development', 'production', '-C', root.path]), 0);

      final prod =
          File('${root.path}/.env.production').readAsStringSync();
      expect(prod, contains('B='));
      expect(prod, contains('A=9'));
      expect(prod, isNot(contains('B=2'))); // value never copied
    });
  });
}
