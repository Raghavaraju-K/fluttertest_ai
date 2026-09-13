import 'dart:convert';

import 'package:args/command_runner.dart';

import '../../generation/dart_test_writer.dart';
import '../../generation/test_plan_builder.dart';
import '../../project/plan_models.dart';
import '../../reporting/console_reporter.dart';
import '../project_service.dart';

class GenerateCommand extends Command<int> {
  GenerateCommand({
    ProjectService? service,
    TestPlanBuilder? builder,
    DartTestWriter? writer,
  })  : _service = service ?? ProjectService(),
        _builder = builder ?? TestPlanBuilder(),
        _writer = writer ?? DartTestWriter() {
    argParser
      ..addOption(
        'type',
        allowed: ['unit', 'widget', 'integration'],
        help: 'Restrict generation to one kind of test.',
      )
      ..addFlag('dry-run', negatable: false, help: 'Plan without writing.')
      ..addFlag(
        'force',
        negatable: false,
        help: 'Refresh generated tests (handwritten tests stay untouched).',
      )
      ..addFlag('json', negatable: false, help: 'Emit machine JSON.');
  }
  final ProjectService _service;
  final TestPlanBuilder _builder;
  final DartTestWriter _writer;

  @override
  String get name => 'generate';

  @override
  String get description => 'Generate tests only under test/.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    final analysis = await _service.analyze(rest.isEmpty ? '.' : rest.first);
    final type = argResults?['type'] as String?;
    final kind = type == null ? null : TestKind.values.byName(type);
    final plan = _builder.build(analysis, only: kind);
    final result = await _writer.write(
      plan,
      analysis,
      dryRun: argResults?['dry-run'] as bool? ?? false,
      force: argResults?['force'] as bool? ?? false,
    );
    final json = argResults?['json'] as bool? ?? false;
    if (json) {
      print(const JsonEncoder.withIndent('  ').convert({
        'written': result.written,
        'skipped': result.skipped,
        'plan': plan.toJson(),
      }));
    } else {
      final reporter = ConsoleReporter();
      reporter.banner();
      reporter.section('Generating tests...');
      for (final path in result.written) {
        reporter.line(path);
      }
      for (final reason in result.skipped) {
        reporter.line(reason, ok: null);
      }
      if (result.written.isEmpty) {
        reporter.line('No tests were written.', ok: null);
      }
    }
    return 0;
  }
}
