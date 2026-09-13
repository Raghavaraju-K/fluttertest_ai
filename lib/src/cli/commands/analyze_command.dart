import 'package:args/command_runner.dart';
import '../../reporting/console_reporter.dart';
import '../project_service.dart';

class AnalyzeCommand extends Command<int> {
  AnalyzeCommand({ProjectService? service})
      : _service = service ?? ProjectService() {
    argParser.addFlag('json', negatable: false);
  }
  final ProjectService _service;
  @override
  String get name => 'analyze';
  @override
  String get description =>
      'Analyze Dart files and produce a conservative test plan.';
  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    final analysis = await _service.analyze(rest.isEmpty ? '.' : rest.first);
    if (argResults!['json'] as bool) {
      print(analysis.toPrettyJson());
    } else {
      ConsoleReporter().analysis(analysis);
    }
    return 0;
  }
}
