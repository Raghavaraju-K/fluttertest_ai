import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../project/plan_models.dart';
import '../templates/templates.dart';
import 'test_failure_parser.dart';

/// Runs only the tests FlutterTest AI generated (ownership marker required)
/// through `flutter test --machine`, enforces a hard timeout, and stores
/// sanitized reports under `.fluttertest_ai/runs/`.
class FlutterTestRunner {
  FlutterTestRunner({TestFailureParser? parser, Duration? timeout})
      : _parser = parser ?? TestFailureParser(),
        _timeout = timeout ?? const Duration(minutes: 15);
  final TestFailureParser _parser;
  final Duration _timeout;

  Future<TestRunResult> run(String root) async {
    final generated = await _generatedTests(root);
    final reportDir = Directory(p.join(root, '.fluttertest_ai', 'runs'));
    await reportDir.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final reportPath = p.join(reportDir.path, '$stamp.json');
    if (generated.isEmpty) {
      const result = TestRunResult(
        exitCode: 0,
        passed: 0,
        failed: 0,
        skipped: 0,
        compilationErrors: 0,
        output: 'No generated tests found.',
        reportPath: 'none',
      );
      await _persist(root, reportPath, result);
      return TestRunResult(
        exitCode: result.exitCode,
        passed: result.passed,
        failed: result.failed,
        skipped: result.skipped,
        compilationErrors: result.compilationErrors,
        output: result.output,
        reportPath: reportPath,
      );
    }
    final packageConfig =
        File(p.join(root, '.dart_tool', 'package_config.json'));
    if (!await packageConfig.exists()) {
      // Non-destructive dependency resolution so generated tests can compile.
      // `flutter pub get` never edits pubspec.yaml.
      await _run('flutter', const ['pub', 'get'], root);
    }
    final process =
        await _run('flutter', ['test', '--machine', ...generated], root);
    final raw = '${process.stdout}\n${process.stderr}';
    final parsed = _parser.parseMachine(process.exitCode, raw, reportPath);
    await _persist(root, reportPath, parsed.result);
    return parsed.result;
  }

  /// Loads the most recent sanitized run report, if any.
  Future<TestRunResult?> latest(String root) async {
    final file = File(p.join(root, '.fluttertest_ai', 'latest.json'));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      int intOf(String key) => decoded[key] is int ? decoded[key] as int : 0;
      return TestRunResult(
        exitCode: intOf('exitCode'),
        passed: intOf('passed'),
        failed: intOf('failed'),
        skipped: intOf('skipped'),
        compilationErrors: intOf('compilationErrors'),
        output: decoded['output']?.toString() ?? '',
        reportPath: decoded['reportPath']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> _generatedTests(String root) async {
    final generated = <String>[];
    final testRoot = Directory(p.join(root, 'test'));
    if (!await testRoot.exists()) return generated;
    await for (final entity
        in testRoot.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      if ((await entity.readAsString()).contains(generatedMarker)) {
        generated.add(p.relative(entity.path, from: root));
      }
    }
    return generated;
  }

  Future<void> _persist(
      String root, String reportPath, TestRunResult result) async {
    final encoder = const JsonEncoder.withIndent('  ');
    final payload = <String, Object?>{
      ...result.toJson(),
      'output': result.output,
    };
    if (result.reportPath != 'none') {
      await File(reportPath).writeAsString(encoder.convert(payload));
    }
    await File(p.join(root, '.fluttertest_ai', 'latest.json'))
        .writeAsString(encoder.convert(payload));
  }

  /// [Process.run] with a hard timeout; the child process is killed when the
  /// timeout elapses so a hanging test can never stall the CLI.
  Future<ProcessResult> _run(String executable, List<String> arguments,
      String workingDirectory) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final drains = <Future<void>>[
      _drain(process.stdout, stdoutBuffer),
      _drain(process.stderr, stderrBuffer),
    ];
    final exitCode = await process.exitCode.timeout(_timeout, onTimeout: () {
      process.kill();
      return -9;
    });
    await Future.wait(drains);
    return ProcessResult(process.pid, exitCode, stdoutBuffer.toString(),
        stderrBuffer.toString());
  }

  Future<void> _drain(Stream<List<int>> stream, StringBuffer buffer) async {
    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer.write(chunk);
    }
  }
}
