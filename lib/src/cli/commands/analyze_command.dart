import 'dart:convert';

import 'package:args/command_runner.dart';

import '../../reporting/console_reporter.dart';
import '../project_service.dart';

class AnalyzeCommand extends Command<int> {
  AnalyzeCommand({ProjectService? service})
      : _service = service ?? ProjectService() {
    argParser.addFlag('json', negatable: false, help: 'Emit machine JSON.');
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
    if (argResults?['json'] as bool? ?? false) {
      print(const JsonEncoder.withIndent('  ').convert(analysis.toJson()));
      return 0;
    }
    ConsoleReporter().analysis(analysis);
    return 0;
  }
}
