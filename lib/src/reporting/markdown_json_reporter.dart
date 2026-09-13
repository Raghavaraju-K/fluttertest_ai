import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../execution/test_failure_parser.dart';
import '../project/models.dart';
import '../project/plan_models.dart';

/// Writes sanitized JSON and Markdown reports under `.fluttertest_ai/`.
///
/// Environment-variable values are never included: run output is redacted
/// through [TestFailureParser.redact] before being persisted, and saved
/// reports only contain the detected state manager, analyzed files, the test
/// plan, results, skipped reasons, confidence scores, and limitations.
class MarkdownJsonReporter {
  Future<List<String>> write(
    String root,
    ProjectAnalysis analysis,
    TestPlan plan, {
    TestRunResult? run,
  }) async {
    final dir = Directory(p.join(root, '.fluttertest_ai'));
    await dir.create(recursive: true);
    final jsonFile = File(p.join(dir.path, 'report.json'));
    final markdownFile = File(p.join(dir.path, 'report.md'));
    final data = <String, Object?>{
      'tool': 'FlutterTest AI',
      'analysis': analysis.toJson(),
      'plan': plan.toJson(),
      if (run != null)
        'run': <String, Object?>{
          'exitCode': run.exitCode,
          'passed': run.passed,
          'failed': run.failed,
          'skipped': run.skipped,
          'compilationErrors': run.compilationErrors,
        },
      'limitations': const [
        'Generated tests are conservative heuristics and always require '
            'human review.',
        'Widgets reading inherited state that cannot be constructed safely '
            'are skipped with an explanation.',
        'A generated test is only reported as passing after `flutter test` '
            'exits successfully.',
      ],
    };
    await jsonFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await markdownFile.writeAsString(_markdown(analysis, plan, run));
    return [jsonFile.path, markdownFile.path];
  }

  String _markdown(
      ProjectAnalysis analysis, TestPlan plan, TestRunResult? run) {
    final state = analysis.stateManagement;
    final buffer = StringBuffer()
      ..writeln('# FlutterTest AI report')
      ..writeln()
      ..writeln('- State management: ${state.framework.label} '
          '(${(state.confidence * 100).round()}% confidence, '
          'adapter: ${state.adapter})')
      ..writeln('- Analyzed files: ${analysis.files.length}')
      ..writeln('- Planned tests: ${plan.items.length}')
      ..writeln('- Skipped: ${plan.skipped.length}')
      ..writeln();
    buffer
      ..writeln('## Test plan')
      ..writeln();
    for (final item in plan.items) {
      buffer.writeln('- ${p.relative(item.output, from: analysis.root)} '
          '(${item.kind.name}, confidence ${item.confidence.toStringAsFixed(2)})');
    }
    if (plan.skipped.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Skipped')
        ..writeln();
      for (final reason in plan.skipped) {
        buffer.writeln('- $reason');
      }
    }
    if (run != null) {
      buffer
        ..writeln()
        ..writeln('## Last generated-test run')
        ..writeln()
        ..writeln('- Passed: ${run.passed}')
        ..writeln('- Failed: ${run.failed}')
        ..writeln('- Skipped: ${run.skipped}')
        ..writeln('- Compilation errors: ${run.compilationErrors}')
        ..writeln('- Exit code: ${run.exitCode}');
    }
    buffer
      ..writeln()
      ..writeln('## Evidence')
      ..writeln();
    for (final evidence in state.evidence) {
      buffer.writeln('- ${evidence.kind}: ${evidence.value}');
    }
    buffer
      ..writeln()
      ..writeln('## Limitations')
      ..writeln()
      ..writeln('Generated tests are conservative heuristics and require '
          'review. Environment-variable values are redacted from all saved '
          'run output.')
      ..writeln();
    return buffer.toString();
  }
}
