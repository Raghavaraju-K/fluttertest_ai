import 'package:args/command_runner.dart';
import '../../project/flutter_project_detector.dart';
import '../project_service.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand({ProjectService? service, FlutterProjectDetector? detector})
      : _service = service ?? ProjectService(),
        _detector = detector ?? FlutterProjectDetector();
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
    final flutter = await _service.flutterVersion();
    final dart = await _service.dartVersion();
    final project = await _detector.isFlutterProject(root);
    if (flutter == null) {
      print('✗ Flutter was not found');
    } else {
      print('✓ $flutter');
    }
    if (dart == null) {
      print('✗ Dart was not found');
    } else {
      print('✓ $dart');
    }
    if (!project) {
      print('✗ Flutter project not detected');
      return 1;
    }
    final analysis = await _service.analyze(root);
    print('✓ Flutter project: ${analysis.projectName}');
    print('✓ State management: ${analysis.stateManagement.framework.name}');
    return flutter == null || dart == null ? 1 : 0;
  }
}
