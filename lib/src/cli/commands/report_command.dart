import 'package:args/command_runner.dart';

import '../../execution/flutter_test_runner.dart';
import '../../generation/test_plan_builder.dart';
import '../../project/plan_models.dart';
import '../../reporting/console_reporter.dart';
import '../../reporting/markdown_json_reporter.dart';
import '../project_service.dart';

class ReportCommand extends Command<int> {
  ReportCommand({
    ProjectService? service,
    TestPlanBuilder? builder,
    MarkdownJsonReporter? reporter,
    ConsoleReporter? console,
  })  : _service = service ?? ProjectService(),
        _builder = builder ?? TestPlanBuilder(),
        _reporter = reporter ?? MarkdownJsonReporter(),
        _console = console ?? ConsoleReporter();
  final ProjectService _service;
  final TestPlanBuilder _builder;
  final MarkdownJsonReporter _reporter;
  final ConsoleReporter _console;

  @override
  String get name => 'report';

  @override
  String get description =>
      'Write JSON and Markdown reports under .fluttertest_ai/.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    final root = rest.isEmpty ? '.' : rest.first;
    _console.banner();
    final analysis = await _service.analyze(root);
    final plan = _builder.build(analysis);
    final run = await _runLatest(root);
    final files = await _reporter.write(root, analysis, plan, run: run);
    for (final file in files) {
      _console.line(file);
    }
    return 0;
  }

  Future<TestRunResult?> _runLatest(String root) async =>
      FlutterTestRunner().latest(root);
}
