import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../project/plan_models.dart';
import 'test_failure_parser.dart';

class FlutterTestRunner {
  FlutterTestRunner({TestFailureParser? parser})
      : _parser = parser ?? TestFailureParser();
  final TestFailureParser _parser;
  Future<TestRunResult> run(String root) async {
    final generated = <String>[];
    final testRoot = Directory(p.join(root, 'test'));
    if (await testRoot.exists()) {
      await for (final entity in testRoot.list(recursive: true)) {
        if (entity is File &&
            entity.path.endsWith('_test.dart') &&
            (await entity.readAsString())
                .contains('fluttertest_ai: generated')) {
          generated.add(p.relative(entity.path, from: root));
        }
      }
    }
    final reportDir = Directory(p.join(root, '.fluttertest_ai', 'runs'));
    await reportDir.create(recursive: true);
    final reportPath = p.join(reportDir.path,
        '${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.json');
    if (generated.isEmpty) {
      final result = TestRunResult(
          exitCode: 0,
          passed: 0,
          failed: 0,
          skipped: 0,
          compilationErrors: 0,
          output: 'No generated tests found.',
          reportPath: reportPath);
      await File(reportPath).writeAsString(jsonEncode(result.toJson()));
      return result;
    }
    final process = await Process.run('flutter', ['test', ...generated],
        workingDirectory: root, runInShell: Platform.isWindows);
    final output = _sanitize('${process.stdout}\n${process.stderr}');
    final result = _parser.parse(process.exitCode, output, reportPath);
    await File(reportPath).writeAsString(const JsonEncoder.withIndent('  ')
        .convert({...result.toJson(), 'output': output}));
    return result;
  }

  String _sanitize(String text) => text.replaceAllMapped(
      RegExp(r'(api[_-]?key|token|secret|password)\s*[=:]\s*\S+',
          caseSensitive: false, multiLine: true),
      (match) => '${match.group(1)}=[REDACTED]');
}
