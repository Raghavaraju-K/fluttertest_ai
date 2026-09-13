import 'dart:convert';
import 'package:args/command_runner.dart';
import '../../generation/dart_test_writer.dart';
import '../../generation/test_plan_builder.dart';
import '../../project/plan_models.dart';
import '../project_service.dart';

class GenerateCommand extends Command<int> {
  GenerateCommand(
      {ProjectService? service,
      TestPlanBuilder? builder,
      DartTestWriter? writer})
      : _service = service ?? ProjectService(),
        _builder = builder ?? TestPlanBuilder(),
        _writer = writer ?? DartTestWriter() {
    argParser
      ..addOption('type', allowed: ['unit', 'widget', 'integration'])
      ..addFlag('dry-run', negatable: false)
      ..addFlag('force', negatable: false)
      ..addFlag('json', negatable: false);
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
    final type = argResults!['type'] as String?;
    final kind = type == null ? null : TestKind.values.byName(type);
    final plan = _builder.build(analysis, only: kind);
    final result = await _writer.write(plan, analysis,
        dryRun: argResults!['dry-run'] as bool,
        force: argResults!['force'] as bool);
    if (argResults!['json'] as bool) {
      print(jsonEncode({
        'plan': plan.toJson(),
        'written': result.written,
        'skipped': result.skipped
      }));
    } else {
      for (final path in result.written) {
        print('✓ $path');
      }
      for (final reason in result.skipped) {
        print('– $reason');
      }
    }
    return 0;
  }
}
