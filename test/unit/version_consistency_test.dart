import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';
import 'package:fluttertest_ai/fluttertest_ai.dart';

void main() {
  test('pubspec.yaml version matches lib/src/version.dart packageVersion',
      () async {
    final pubspecPath = p.join(Directory.current.path, 'pubspec.yaml');
    final pubspecContent = await File(pubspecPath).readAsString();
    final pubspecYaml = loadYaml(pubspecContent) as YamlMap;
    final pubspecVersion = pubspecYaml['version'] as String;

    expect(
      packageVersion,
      pubspecVersion,
      reason: 'Version mismatch: pubspec.yaml has version "$pubspecVersion" '
          'but lib/src/version.dart has packageVersion "$packageVersion". '
          'Update both files so they match before releasing.',
    );
  });
}
