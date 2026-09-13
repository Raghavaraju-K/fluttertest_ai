import 'dart:io';
import 'package:yaml/yaml.dart';

class PubspecReader {
  Future<Map<String, dynamic>> read(String root) async {
    final file = File('$root${Platform.pathSeparator}pubspec.yaml');
    if (!await file.exists()) return {};
    final yaml = loadYaml(await file.readAsString());
    return _plain(yaml) as Map<String, dynamic>;
  }

  dynamic _plain(dynamic value) {
    if (value is YamlMap) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _plain(entry.value)
      };
    }
    if (value is YamlList) return value.map(_plain).toList();
    return value;
  }
}
