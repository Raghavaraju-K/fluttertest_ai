import 'dart:io';
import 'package:path/path.dart' as p;

class DartFileDiscovery {
  Future<List<File>> discoverLibFiles(String root) async {
    final lib = Directory(p.join(root, 'lib'));
    if (!await lib.exists()) return [];
    final files = <File>[];
    await for (final entity in lib.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          !entity.path.endsWith('.g.dart') &&
          !entity.path.endsWith('.freezed.dart')) {
        files.add(entity);
      }
    }
    return files;
  }

  Future<List<File>> discoverTests(String root) async {
    final test = Directory(p.join(root, 'test'));
    if (!await test.exists()) return [];
    return test
        .list(recursive: true)
        .where((e) => e is File && e.path.endsWith('_test.dart'))
        .cast<File>()
        .toList();
  }
}
