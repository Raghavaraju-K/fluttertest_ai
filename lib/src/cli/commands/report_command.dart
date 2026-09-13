import 'package:args/command_runner.dart';
import '../../generation/test_plan_builder.dart';
import '../../reporting/markdown_json_reporter.dart';
import '../project_service.dart';

class ReportCommand extends Command<int> {
  ReportCommand(
      {ProjectService? service,
      TestPlanBuilder? builder,
      MarkdownJsonReporter? reporter})
      : _service = service ?? ProjectService(),
        _builder = builder ?? TestPlanBuilder(),
        _reporter = reporter ?? MarkdownJsonReporter();
  final ProjectService _service;
  final TestPlanBuilder _builder;
  final MarkdownJsonReporter _reporter;
  @override
  String get name => 'report';
  @override
  String get description =>
      'Write JSON and Markdown reports under .fluttertest_ai/.';
  @override
  Future<int> run() async {
    final analysis = await _service.analyze('.');
    final files =
        await _reporter.write('.', analysis, _builder.build(analysis));
    for (final file in files) {
      print('✓ $file');
    }
    return 0;
  }
}
