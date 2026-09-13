import 'dart:io';
import 'package:path/path.dart' as p;

class DartFileDiscovery {
  Future<List<File>> discoverLibFiles(String root) async {
    final lib = Directory(p.join(root, 'lib'));
    if (!await lib.exists()) return [];
    final files = <File>[];
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (_isGeneratedOutput(entity.path)) continue;
        files.add(entity);
      }
    }
    return files;
  }

  Future<List<File>> discoverTests(String root) async {
    final test = Directory(p.join(root, 'test'));
    if (!await test.exists()) return [];
    final files = <File>[];
    await for (final entity in test.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('_test.dart')) {
        files.add(entity);
      }
    }
    return files;
  }

  /// Build artifacts and generated sources are never analyzed.
  bool _isGeneratedOutput(String path) {
    final segments = p.split(path).map((segment) => segment).toSet();
    return segments.intersection(const {
          '.dart_tool',
          'build',
          '.git',
          'generated_plugin_registrant.dart',
        }).isNotEmpty ||
        path.endsWith('.g.dart') ||
        path.endsWith('.freezed.dart') ||
        path.endsWith('.gr.dart');
  }
}
