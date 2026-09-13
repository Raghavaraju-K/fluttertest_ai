import 'dart:io';
import 'package:path/path.dart' as p;
import 'pubspec_reader.dart';

class FlutterProjectDetector {
  FlutterProjectDetector({PubspecReader? reader})
      : _reader = reader ?? PubspecReader();
  final PubspecReader _reader;
  Future<bool> isFlutterProject(String root) async {
    final spec = await _reader.read(root);
    final dependencies = <String, dynamic>{
      ...?((spec['dependencies'] as Map?)?.cast<String, dynamic>()),
      ...?((spec['dev_dependencies'] as Map?)?.cast<String, dynamic>())
    };
    return dependencies.containsKey('flutter') ||
        await Directory(p.join(root, 'lib')).exists() &&
            await File(p.join(root, 'pubspec.yaml')).exists();
  }
}
