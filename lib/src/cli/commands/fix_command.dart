import 'package:args/command_runner.dart';
import '../../execution/flutter_test_runner.dart';
import '../../execution/generated_test_repairer.dart';
import '../../project/plan_models.dart';

class FixCommand extends Command<int> {
  FixCommand({GeneratedTestRepairer? repairer, FlutterTestRunner? runner})
      : _repairer = repairer ?? GeneratedTestRepairer(),
        _runner = runner ?? FlutterTestRunner() {
    argParser.addOption('attempts', defaultsTo: '3');
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
    final attempts = int.tryParse(argResults!['attempts'] as String) ?? 3;
    TestRunResult result = await _runner.run('.');
    for (var attempt = 0; attempt < attempts && !result.succeeded; attempt++) {
      final repair = await _repairer.repair('.', result.output);
      for (final file in repair.changed) {
        print('✓ Repaired $file');
      }
      for (final item in repair.unrepaired) {
        print('– $item');
      }
      if (repair.changed.isEmpty) break;
      result = await _runner.run('.');
    }
    if (result.succeeded) {
      print('✓ Re-ran tests: ${result.passed} passed');
    } else {
      print('✗ Tests could not be safely repaired');
    }
    return result.exitCode;
  }
}
