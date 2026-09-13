import 'package:path/path.dart' as p;

import '../adapters/state_management_adapter.dart';
import '../project/models.dart';
import '../project/plan_models.dart';
import '../templates/templates.dart';

/// Generates a launch-and-render smoke test under `integration_test/` when
/// the project already depends on `integration_test` and exposes a safely
/// constructible root widget. The dependency is never added automatically;
/// missing prerequisites produce an explained skip instead of broken code.
class IntegrationTestGenerator {
  const IntegrationTestGenerator();

  GenerationOutcome generate(TestPlanItem item, ProjectAnalysis analysis) {
    if (!analysis.dependencies.contains('integration_test')) {
      return const GenerationOutcome(null, notes: [
        'integration_test dependency is required but missing; FlutterTest AI '
            'never modifies pubspec.yaml, so this test was skipped',
      ]);
    }
    final source = _launchSource(analysis);
    if (source == null || source.constructibleWidgets.isEmpty) {
      return const GenerationOutcome(null, notes: [
        'no launchable root widget found (a public, no-required-argument '
            'widget in lib/main.dart is required)',
      ]);
    }
    final widget = source.constructibleWidgets.first;
    final adapter = StateManagementAdapters.forFramework(
        analysis.stateManagement.framework);
    final cupertinoOnly = source.hasCupertino && !source.hasMaterial;
    final app = cupertinoOnly ? 'CupertinoApp' : 'MaterialApp';
    final harness = adapter.wrapHarness('$app(home: ${widget.name}())');
    final imports = <String>[
      cupertinoOnly
          ? "import 'package:flutter/cupertino.dart';"
          : "import 'package:flutter/material.dart';",
      "import 'package:flutter_test/flutter_test.dart';",
      "import 'package:integration_test/integration_test.dart';",
      ...adapter.extraImports,
      "import '${packageImport(source.path, analysis.root, analysis.projectName)}';",
    ].join('\n');
    final content = '${generatedFileHeader(item.confidence)}'
        '$imports\n\n'
        'void main() {\n'
        '  IntegrationTestWidgetsFlutterBinding.ensureInitialized();\n'
        '  testWidgets(\'app smoke: ${widget.name} renders\', (tester) async {\n'
        '    await tester.pumpWidget($harness);\n'
        '    await tester.pump();\n'
        '    expect(find.byType(${widget.name}), findsOneWidget);\n'
        '  });\n'
        '}\n'
        '// $generatedRegionEnd\n';
    return GenerationOutcome(content);
  }

  DartFileInfo? _launchSource(ProjectAnalysis analysis) {
    DartFileInfo? main;
    for (final file in analysis.files) {
      if (p.basename(file.path) != 'main.dart') continue;
      if (p.basenameWithoutExtension(file.path) != 'main.dart') continue;
      main ??= file;
      if (file.constructibleWidgets.isNotEmpty) return file;
    }
    return main;
  }
}
