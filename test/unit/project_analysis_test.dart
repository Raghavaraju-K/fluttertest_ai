import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:fluttertest_ai/fluttertest_ai.dart';

void main() {
  final fixtures = p.join(Directory.current.path, 'test', 'fixtures');

  test('detects a Flutter project and Riverpod adapter from fixture evidence',
      () async {
    final root = p.join(fixtures, 'riverpod_async');
    expect(await FlutterProjectDetector().isFlutterProject(root), isTrue);
    final analysis = await ProjectService().analyze(root);
    expect(analysis.stateManagement.framework, StateManagement.riverpod);
    expect(analysis.stateManagement.adapter, 'riverpodAdapter');
  });

  test('builds a unit plan and writes only beneath test', () async {
    final temp = await Directory.systemTemp.createTemp('fluttertest-ai-');
    addTearDown(() => temp.delete(recursive: true));
    await Directory(p.join(temp.path, 'lib')).create();
    await File(p.join(temp.path, 'pubspec.yaml'))
        .writeAsString('name: sample\ndependencies:\n  flutter: any\n');
    await File(p.join(temp.path, 'lib', 'email.dart'))
        .writeAsString('bool validEmail() => true;');
    final analysis = await ProjectService().analyze(temp.path);
    final plan = TestPlanBuilder().build(analysis, only: TestKind.unit);
    final result = await DartTestWriter().write(plan, analysis);
    expect(result.written, hasLength(1));
    expect(File(p.join(temp.path, 'test', 'email_test.dart')).existsSync(),
        isTrue);
    expect(File(p.join(temp.path, 'lib', 'email_test.dart')).existsSync(),
        isFalse);
  });

  test('never overwrites a handwritten test', () async {
    final temp = await Directory.systemTemp.createTemp('fluttertest-ai-');
    addTearDown(() => temp.delete(recursive: true));
    await Directory(p.join(temp.path, 'lib')).create();
    await Directory(p.join(temp.path, 'test')).create();
    await File(p.join(temp.path, 'pubspec.yaml'))
        .writeAsString('name: sample\ndependencies:\n  flutter: any\n');
    await File(p.join(temp.path, 'lib', 'email.dart'))
        .writeAsString('bool validEmail() => true;');
    final handwritten = File(p.join(temp.path, 'test', 'email_test.dart'))
      ..writeAsStringSync('// mine');
    final analysis = await ProjectService().analyze(temp.path);
    final result = await DartTestWriter().write(
        TestPlanBuilder().build(analysis, only: TestKind.unit), analysis,
        force: true);
    expect(result.written, isEmpty);
    expect(await handwritten.readAsString(), '// mine');
  });
}
