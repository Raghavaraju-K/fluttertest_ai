import 'dart:io';
import 'package:path/path.dart' as p;

class RepairResult {
  const RepairResult(this.changed, this.unrepaired);
  final List<String> changed, unrepaired;
}

/// Applies only mechanical, reversible changes inside files marked as generated.
class GeneratedTestRepairer {
  Future<RepairResult> repair(String root, String failureOutput) async {
    final changed = <String>[], unrepaired = <String>[];
    final test = Directory(p.join(root, 'test'));
    if (!await test.exists()) {
      return RepairResult(changed, ['No test directory found.']);
    }
    await for (final entity in test.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      var source = await entity.readAsString();
      if (!source.contains('fluttertest_ai: generated')) continue;
      final original = source;
      if (failureOutput.contains('ProviderScope') &&
          !source.contains('ProviderScope(child:')) {
        source = source
            .replaceFirst(
                'MaterialApp(home:', 'ProviderScope(child: MaterialApp(home:')
            .replaceFirst(');\n    await tester.pump();',
                '));\n    await tester.pump();');
      }
      if (failureOutput.contains('found: 0') &&
          source.contains('await tester.pump();')) {
        source = source.replaceFirst(
            'await tester.pump();', 'await tester.pumpAndSettle();');
      }
      if (failureOutput.contains('BlocProvider') &&
          source.contains('BlocBuilder<') &&
          !source.contains('BlocProvider<')) {
        final blocClass = _extractBlocClass(failureOutput);
        if (blocClass != null && _constructible(source, root, blocClass)) {
          source = source.replaceFirst(
              'MaterialApp(home:',
              'BlocProvider<$blocClass>(create: (_) => $blocClass(), child: MaterialApp(home:');
          source = source.replaceFirst(
              ');\n    await tester.pump();',
              '));\n    await tester.pump();');
        }
      }
      if (failureOutput.contains("Target of URI hasn't been found") &&
          source.contains("import 'package:")) {
        source = source.replaceAll(
            RegExp(r"import 'package:[^']+/lib/"), "import 'package:");
      }
      if (source != original) {
        await entity.writeAsString(source);
        changed.add(p.relative(entity.path, from: root));
      }
    }
    if (changed.isEmpty && failureOutput.isNotEmpty) {
      unrepaired.add('No safe deterministic repair matched the failure.');
    }
    return RepairResult(changed, unrepaired);
  }

  String? _extractBlocClass(String failureOutput) {
    final match = RegExp(r'BlocBuilder<(\w+)').firstMatch(failureOutput);
    return match?.group(1);
  }

  bool _constructible(String testSource, String root, String typeName) {
    final projectName = _projectName(root);
    if (projectName == null) return false;
    final prefix = 'package:$projectName/';
    final importRegex = RegExp("import '(package:[^']+)';");
    for (final match in importRegex.allMatches(testSource)) {
      final uri = match.group(1)!;
      if (!uri.startsWith(prefix)) continue;
      final file = File(p.join(root, 'lib', uri.substring(prefix.length)));
      if (!file.existsSync()) continue;
      try {
        // Simple check: does the file contain the class name with a constructor?
        final content = file.readAsStringSync();
        if (content.contains('class $typeName') &&
            (content.contains('const $typeName(') ||
                content.contains('$typeName({') ||
                content.contains('$typeName()'))) {
          return true;
        }
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  String? _projectName(String root) {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return null;
    final content = pubspec.readAsStringSync();
    final match = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(content);
    return match?.group(1)?.trim();
  }
}
