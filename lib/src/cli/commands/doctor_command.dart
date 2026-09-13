import 'package:args/command_runner.dart';

import '../../project/flutter_project_detector.dart';
import '../../project/models.dart' show StateManagementLabel;
import '../../reporting/console_reporter.dart';
import '../project_service.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand({ProjectService? service, FlutterProjectDetector? detector})
      : _service = service ?? ProjectService(),
        _detector = detector ?? FlutterProjectDetector() {
    argParser.addOption('path',
        help: 'Project path (defaults to the '
            'first positional argument or the current directory).');
  }
  final ProjectService _service;
  final FlutterProjectDetector _detector;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Verify Flutter, Dart, and the current Flutter project.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    final root = rest.isEmpty ? '.' : rest.first;
    final reporter = ConsoleReporter();
    reporter.banner();
    var healthy = true;

    final flutter = await _service.flutterVersion();
    final dart = await _service.dartVersion();
    if (flutter == null) {
      reporter.line('Flutter was not found', ok: false);
      healthy = false;
    } else {
      reporter.line(flutter);
    }
    if (dart == null) {
      reporter.line('Dart was not found', ok: false);
      healthy = false;
    } else {
      reporter.line(dart);
    }

    if (!await _detector.isFlutterProject(root)) {
      reporter.line('Flutter project not detected in $root', ok: false);
      return 1;
    }
    final analysis = await _service.analyze(root);
    reporter.line('Flutter project: ${analysis.projectName}');
    reporter.line(
        'State management: ${analysis.stateManagement.framework.label} '
        '(${(analysis.stateManagement.confidence * 100).round()}% confidence, '
        'adapter: ${analysis.stateManagement.adapter})');
    reporter.line('Screens/widgets detected: ${analysis.widgetCount}');
    reporter.line('Testable classes detected: ${analysis.testableClassCount}');
    reporter.line('Existing tests found: ${analysis.existingTests.length}');
    return healthy ? 0 : 1;
  }
}
