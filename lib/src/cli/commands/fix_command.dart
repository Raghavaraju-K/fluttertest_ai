import 'package:args/command_runner.dart';

import '../../execution/flutter_test_runner.dart';
import '../../execution/generated_test_repairer.dart';
import '../../reporting/console_reporter.dart';

class FixCommand extends Command<int> {
  FixCommand({GeneratedTestRepairer? repairer, FlutterTestRunner? runner})
      : _repairer = repairer ?? GeneratedTestRepairer(),
        _runner = runner ?? FlutterTestRunner() {
    argParser.addOption(
      'attempts',
      defaultsTo: '3',
      help: 'Maximum repair attempts (default: 3).',
    );
  }
  final GeneratedTestRepairer _repairer;
  final FlutterTestRunner _runner;

  @override
  String get name => 'fix';

  @override
  String get description =>
      'Apply safe repairs to generated tests and rerun them.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    final root = rest.isEmpty ? '.' : rest.first;
    final attempts = int.tryParse(argResults?['attempts'] as String) ?? 3;
    final reporter = ConsoleReporter();
    reporter.banner();

    var result = await _runner.run(root);
    for (var attempt = 0; attempt < attempts && !result.succeeded; attempt++) {
      reporter.section('Repairing generated tests (attempt ${attempt + 1})...');
      final repair = await _repairer.repair(root, result);
      for (final description in repair.descriptions) {
        reporter.line(description);
      }
      for (final file in repair.changed) {
        reporter.line(file);
      }
      for (final item in repair.unrepaired) {
        reporter.line(item, ok: null);
      }
      if (repair.changed.isEmpty) break;
      reporter.section('Re-running repaired tests...');
      result = await _runner.run(root);
    }
    reporter.run(result);
    if (!result.succeeded) {
      print('Tests could not be safely repaired; review them manually.');
    }
    print('Report: ${result.reportPath}');
    return result.exitCode;
  }
}
