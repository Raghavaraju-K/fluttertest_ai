import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/dart_source_analyzer.dart';
import '../analysis/state_management_detector.dart';
import '../project/dart_file_discovery.dart';
import '../project/models.dart';
import '../project/pubspec_reader.dart';

/// Facade over project detection, file discovery, AST analysis, and state
/// detection; shared by every CLI command.
class ProjectService {
  ProjectService({
    DartFileDiscovery? discovery,
    DartSourceAnalyzer? analyzer,
    StateManagementDetector? detector,
    PubspecReader? pubspec,
  })  : _discovery = discovery ?? DartFileDiscovery(),
        _analyzer = analyzer ?? DartSourceAnalyzer(),
        _detector = detector ?? StateManagementDetector(),
        _pubspec = pubspec ?? PubspecReader();
  final DartFileDiscovery _discovery;
  final DartSourceAnalyzer _analyzer;
  final StateManagementDetector _detector;
  final PubspecReader _pubspec;

  Future<ProjectAnalysis> analyze(String path) async {
    final root = p.normalize(p.absolute(path));
    final spec = await _pubspec.read(root);
    final dependencies = <String>[
      for (final section in ['dependencies', 'dev_dependencies'])
        ...?((spec[section] as Map?)?.keys.map((key) => key.toString())),
    ];
    final files = <DartFileInfo>[];
    final skipped = <String>[];
    for (final file in await _discovery.discoverLibFiles(root)) {
      try {
        files.add(_analyzer.analyze(file));
      } catch (_) {
        skipped.add(
            '${p.relative(file.path, from: root)}: parser could not inspect file');
      }
    }
    final tests = (await _discovery.discoverTests(root))
        .map((f) => p.relative(f.path, from: root))
        .toList();
    return ProjectAnalysis(
      root: root,
      projectName: spec['name']?.toString() ?? p.basename(root),
      files: files,
      stateManagement: _detector.detect(spec, files),
      existingTests: tests,
      skipped: skipped,
      dependencies: dependencies,
    );
  }

  Future<String?> flutterVersion() async => _version('flutter', ['--version']);

  Future<String?> dartVersion() async => _version('dart', ['--version']);

  Future<String?> _version(String executable, List<String> args) async {
    try {
      final result =
          await Process.run(executable, args, runInShell: Platform.isWindows);
      return result.exitCode == 0
          ? '${result.stdout}${result.stderr}'.split('\n').first.trim()
          : null;
    } catch (_) {
      return null;
    }
  }
}
