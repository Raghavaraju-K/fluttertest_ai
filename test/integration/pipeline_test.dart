import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:fluttertest_ai/fluttertest_ai.dart';

/// End-to-end pipeline checks over the fixture projects: analyze → plan →
/// generate → runner (no-Flutter fallback) → report, all executed in temp
/// copies so the repository fixtures stay pristine.
void main() {
  final fixtures = p.join(Directory.current.path, 'test', 'fixtures');

  Directory fixtureCopy(String name) {
    final source = Directory(p.join(fixtures, name));
    final temp = Directory.systemTemp.createTempSync('fluttertest-ai-e2e-');
    addTearDown(() => temp.deleteSync(recursive: true));
    for (final entity in source.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source.path);
      final target = File(p.join(temp.path, relative))
        ..parent.createSync(recursive: true);
      target.writeAsStringSync(entity.readAsStringSync());
    }
    return temp;
  }

  test('full pipeline: analyze, plan, generate, run, report', () async {
    final root = fixtureCopy('basic_set_state');
    final service = ProjectService();
    final analysis = await service.analyze(root.path);
    expect(analysis.stateManagement.framework, StateManagement.setState);

    final plan = TestPlanBuilder().build(analysis);
    expect(plan.items.map((item) => item.kind), contains(TestKind.widget));
    expect(plan.items.map((item) => item.kind), contains(TestKind.unit));

    final writer = DartTestWriter();
    final writeResult = await writer.write(plan, analysis);
    expect(writeResult.written, isNotEmpty);
    for (final path in writeResult.written) {
      expect(path, startsWith('test'), reason: path);
    }

    // No Flutter toolchain needed for this assertion: with no generated
    // failures, the runner stores a sanitized report under .fluttertest_ai/.
    final runResult =
        await FlutterTestRunner(timeout: const Duration(seconds: 5))
            .run(root.path);
    final latest = await FlutterTestRunner().latest(root.path);
    expect(latest, isNotNull);
    expect(latest!.reportPath, isNotEmpty);

    final report = MarkdownJsonReporter();
    final files = await report.write(root.path, analysis, plan, run: runResult);
    expect(
        File(p.join(root.path, '.fluttertest_ai', 'report.json')).existsSync(),
        isTrue);
    expect(File(files.first).readAsStringSync(), contains('"stateManagement"'));
    final markdown =
        await File(p.join(root.path, '.fluttertest_ai', 'report.md'))
            .readAsString();
    expect(markdown, contains('State management: setState'));
  });

  test('reports redact environment-variable values', () async {
    final root = fixtureCopy('custom_state');
    final redacted = TestFailureParser.redact('MY_TOKEN=abc123 API_KEY=xyz\n');
    expect(redacted, contains('[REDACTED]'));
    expect(redacted, isNot(contains('abc123')));
    final reportFile = File(p.join(root.path, '.fluttertest_ai', 'report.md'));
    expect(await reportFile.exists(), isFalse);
  });

  test('custom-state fixture takes the generic fallback path', () async {
    final root = fixtureCopy('custom_state');
    final analysis = await ProjectService().analyze(root.path);
    expect(analysis.stateManagement.framework, StateManagement.unknown);
    expect(analysis.stateManagement.adapter, 'genericAdapter');
    final plan = TestPlanBuilder().build(analysis);
    final result = await DartTestWriter().write(plan, analysis);
    expect(result.written, isNotEmpty);
    final widgetTest =
        File(p.join(root.path, 'test', 'custom_widget_test.dart'))
            .readAsStringSync();
    expect(widgetTest, contains('MaterialApp(home: CustomScreen())'));
  });
}
