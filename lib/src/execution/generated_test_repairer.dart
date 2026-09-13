import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../analysis/dart_source_analyzer.dart';
import '../project/plan_models.dart';
import '../templates/templates.dart';

class RepairResult {
  const RepairResult(this.changed, this.descriptions, this.unrepaired);
  final List<String> changed;
  final List<String> descriptions;
  final List<String> unrepaired;
}

/// Applies only deterministic, reversible changes inside generated test files
/// (ownership marker required). Handwritten tests and everything under `lib/`
/// are never touched.
class GeneratedTestRepairer {
  Future<RepairResult> repair(String root, TestRunResult run) async {
    final changed = <String>[];
    final descriptions = <String>[];
    final unrepaired = <String>[];
    final testDir = Directory(p.join(root, 'test'));
    if (!await testDir.exists()) {
      return RepairResult(const [], const [], ['No test directory found.']);
    }
    await for (final entity
        in testDir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      final source = await entity.readAsString();
      if (!source.contains(generatedMarker)) continue;
      final relative = p.relative(entity.path, from: root);
      final failures = run.failuresByFile[entity.path] ??
          run.failuresByFile[relative] ??
          const <String>[];
      final output = failures.isNotEmpty ? failures.join('\n') : run.output;
      var updated = source;

      void apply(
        bool condition,
        String description,
        String Function(String source) transform,
      ) {
        if (!condition) return;
        final candidate = transform(updated);
        if (candidate != updated) {
          updated = candidate;
          descriptions.add(description);
        }
      }

      apply(
        output.contains('ProviderScope') && !updated.contains('ProviderScope('),
        'Fixed missing ProviderScope override',
        (source) =>
            _wrapPump(source, (child) => 'ProviderScope(child: $child)'),
      );
      apply(
        output.contains('No Material widget found') &&
            !updated.contains('MaterialApp('),
        'Fixed missing MaterialApp harness',
        (source) => _wrapPump(source, (child) => 'MaterialApp(home: $child)'),
      );
      apply(
        (output.contains('No Cupertino') ||
                output.contains('CupertinoLocalizations')) &&
            !updated.contains('CupertinoApp(') &&
            !updated.contains('MaterialApp('),
        'Fixed missing CupertinoApp harness',
        (source) => _wrapPump(source, (child) => 'CupertinoApp(home: $child)'),
      );
      apply(
        output.contains('BlocProvider.of() called with a context') &&
            updated.contains('BlocBuilder<'),
        'Fixed missing BlocProvider harness',
        (source) => _wrapBlocProvider(source, root),
      );
      apply(
        (output.contains('found: 0') ||
                output.contains('Expected: exactly one matching node')) &&
            updated.contains('await tester.pump();') &&
            !updated.contains('pumpAndSettle'),
        'Switched pump to pumpAndSettle for the failed finder',
        (source) => source.replaceFirst(
            'await tester.pump();', 'await tester.pumpAndSettle();'),
      );
      apply(
        output.contains('pumpAndSettle') &&
            output.contains('timed out') &&
            updated.contains('pumpAndSettle();'),
        'Replaced timed-out pumpAndSettle with a bounded pump',
        (source) => source.replaceFirst('await tester.pumpAndSettle();',
            'await tester.pump(const Duration(milliseconds: 200));'),
      );
      apply(
        output.contains('A Timer is still pending') &&
            updated.contains('pumpAndSettle();'),
        'Replaced pumpAndSettle with a bounded pump to stop pending timers',
        (source) => source.replaceFirst('await tester.pumpAndSettle();',
            'await tester.pump(const Duration(milliseconds: 100));'),
      );
      final projectName = _projectName(root);
      apply(
        projectName != null && updated.contains("package:$projectName/lib/"),
        'Fixed incorrect package import path',
        (source) => source.replaceAll(
            "package:$projectName/lib/", 'package:$projectName/'),
      );
      apply(
        RegExp(r"isn't defined").hasMatch(output) &&
            _usesWidgetTestHelpers(updated) &&
            !updated
                .contains("import 'package:flutter_test/flutter_test.dart';"),
        'Added missing flutter_test import',
        (source) => source.replaceFirst("import 'package:test/test.dart';",
            "import 'package:flutter_test/flutter_test.dart';\nimport 'package:test/test.dart';"),
      );

      if (updated != source) {
        await entity.writeAsString(updated);
        changed.add(relative);
      }
    }
    if (changed.isEmpty && run.output.isNotEmpty) {
      unrepaired
          .add('No safe deterministic repair matched the failure output.');
    }
    return RepairResult(changed, descriptions, unrepaired);
  }

  /// Wraps the first `pumpWidget(<child>)` argument with the given harness.
  /// Uses a non-greedy match without dotAll so multi-line sources don't cause
  /// the capture to run away past the intended `);` terminator.
  String _wrapPump(String source, String Function(String child) wrap) {
    final regex = RegExp(r'await tester\.pumpWidget\((.+?)\);');
    if (!regex.hasMatch(source)) return source;
    return source.replaceFirstMapped(
        regex, (match) => 'await tester.pumpWidget(${wrap(match.group(1)!)});');
  }

  String _wrapBlocProvider(String source, String root) {
    final match =
        RegExp(r'BlocBuilder<([A-Za-z_][A-Za-z0-9_]*)').firstMatch(source);
    if (match == null) return source;
    final blocType = match.group(1)!;
    if (!_constructible(source, root, blocType)) return source;
    return _wrapPump(
      source,
      (child) =>
          'BlocProvider<$blocType>(create: (_) => $blocType(), child: $child)',
    );
  }

  bool _usesWidgetTestHelpers(String source) =>
      source.contains('testWidgets') ||
      source.contains('WidgetTester') ||
      source.contains('tester.pump');

  /// Whether [typeName] is a public class with a no-required-argument
  /// constructor reachable through the test's project imports; only then can
  /// a `create: (_) => $typeName()` harness be generated safely.
  bool _constructible(String testSource, String root, String typeName) {
    final projectName = _projectName(root);
    if (projectName == null) return false;
    final prefix = 'package:$projectName/';
    final importRegex = RegExp("import '(package:[^']+)';");
    for (final match in importRegex.allMatches(testSource)) {
      final uri = match.group(1)!;
      if (!uri.startsWith(prefix)) continue;
      var relative = uri.substring(prefix.length);
      // Normalize incorrect `package:<proj>/lib/...` imports to `lib/...`.
      if (relative.startsWith('lib/')) {
        relative = relative.substring('lib/'.length);
      }
      final file = File(p.join(root, 'lib', relative));
      if (!file.existsSync()) continue;
      try {
        final info = DartSourceAnalyzer().analyze(file);
        for (final clazz in info.classDetails) {
          if (clazz.name == typeName) {
            return clazz.isPubliclyConstructible;
          }
        }
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  String? _projectName(String root) {
    try {
      final file = File(p.join(root, 'pubspec.yaml'));
      if (!file.existsSync()) return null;
      final spec = loadYaml(file.readAsStringSync());
      return spec is YamlMap ? spec['name']?.toString() : null;
    } catch (_) {
      return null;
    }
  }
}
