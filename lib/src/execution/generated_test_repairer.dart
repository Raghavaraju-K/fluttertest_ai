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
          source.contains('flutter_riverpod') &&
          !source.contains('ProviderScope(child:')) {
        source = source
            .replaceFirst(
                'MaterialApp(home:', 'ProviderScope(child: MaterialApp(home:')
            .replaceFirst(');\n    await tester.pump();',
                '));\n    await tester.pump();');
      }
      if (failureOutput.contains('pumpAndSettle') &&
          source.contains('await tester.pump();')) {
        source = source.replaceFirst(
            'await tester.pump();', 'await tester.pumpAndSettle();');
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
}
