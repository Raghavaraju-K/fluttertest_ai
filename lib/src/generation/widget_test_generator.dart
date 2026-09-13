import 'dart:io';

import '../adapters/state_management_adapter.dart';
import '../analysis/dart_source_analyzer.dart';
import '../analysis/widget_analyzer.dart';
import '../project/dart_symbols.dart';
import '../project/models.dart';
import '../project/plan_models.dart';
import '../templates/templates.dart';

/// Generates conservative behavior-based widget tests from public UI
/// signals: renderability, visible text, stable keys, declared button and
/// input-field types, and async-state tolerance.
///
/// Widgets that read inherited state (Provider, BLoC, GetX, ...) are skipped
/// with an explanation instead of generating a test that cannot run; a bare
/// `ProviderScope` makes Riverpod widgets safe.
class WidgetTestGenerator {
  WidgetTestGenerator({WidgetAnalyzer? analyzer})
      : _analyzer = analyzer ?? WidgetAnalyzer();
  final WidgetAnalyzer _analyzer;

  GenerationOutcome generate(TestPlanItem item, ProjectAnalysis analysis) {
    final file = DartSourceAnalyzer().analyze(File(item.source));
    final framework = analysis.stateManagement.framework;
    final adapter = StateManagementAdapters.forFramework(framework);
    final notes = <String>[];
    final candidates = <ClassInfo>[];
    for (final widget in file.constructibleWidgets) {
      if (widget.widgetSuperkind == 'GetView') {
        notes.add('${widget.name}: GetX views require Get.find() state '
            'registration and are skipped');
        continue;
      }
      if (_analyzer.requiresUnsafeState(widget, file, framework)) {
        notes.add('${widget.name}: reads inherited state (${framework.label}) '
            'that cannot be safely constructed automatically; skipped');
        continue;
      }
      candidates.add(widget);
      if (candidates.length == 3) break;
    }
    if (candidates.isEmpty) {
      return GenerationOutcome(
        null,
        notes: notes.isEmpty
            ? ['no safely constructible public widget found']
            : notes,
      );
    }
    final cupertinoOnly = file.hasCupertino && !file.hasMaterial;
    final app = cupertinoOnly ? 'CupertinoApp' : 'MaterialApp';
    final imports = <String>[
      cupertinoOnly
          ? "import 'package:flutter/cupertino.dart';"
          : "import 'package:flutter/material.dart';",
      "import 'package:flutter_test/flutter_test.dart';",
      ...adapter.extraImports,
      "import '${packageImport(item.source, analysis.root, analysis.projectName)}';",
    ].join('\n');
    final tests = <String>[];
    for (final widget in candidates) {
      final harness = adapter.wrapHarness('$app(home: ${widget.name}())');
      tests.add(_renderTest(widget.name, harness));
      for (final text in file.visibleTexts.take(2)) {
        tests.add(_textTest(widget.name, text, harness));
      }
      for (final key in file.keys.take(2)) {
        tests.add(_keyTest(widget.name, key, harness));
      }
      final buttons = file.buttonTypes
          .where((type) => cupertinoOnly
              ? type.startsWith('Cupertino')
              : !type.startsWith('Cupertino'))
          .take(1);
      for (final button in buttons) {
        tests.add(_typeTest(widget.name, button, harness, 'button'));
      }
      final fields = file.textFieldTypes
          .where((type) => cupertinoOnly
              ? type.startsWith('Cupertino')
              : !type.startsWith('Cupertino'))
          .take(1);
      for (final field in fields) {
        tests.add(_typeTest(widget.name, field, harness, 'input field'));
      }
      if (file.hasAsyncBuilder) {
        tests.add(_asyncTest(widget.name, harness));
      }
    }
    final content = '${generatedFileHeader(item.confidence)}'
        '$imports\n\n'
        'void main() {\n'
        '${tests.join('\n\n')}\n'
        '}\n'
        '// $generatedRegionEnd\n';
    return GenerationOutcome(content, notes: notes);
  }

  String _renderTest(String name, String harness) =>
      "  testWidgets('$name renders without crashing', (tester) async {\n"
      '    await tester.pumpWidget($harness);\n'
      '    await tester.pump();\n'
      '    expect(find.byType($name), findsOneWidget);\n'
      '  });';

  String _textTest(String name, String text, String harness) =>
      "  // Heuristic: the source declares this visible text.\n"
      "  testWidgets('$name shows \"${_escape(text)}\"', (tester) async {\n"
      '    await tester.pumpWidget($harness);\n'
      '    await tester.pump();\n'
      "    expect(find.text('${_escape(text)}'), findsWidgets);\n"
      '  });';

  String _keyTest(String name, String key, String harness) =>
      "  // Heuristic: the source declares this key.\n"
      "  testWidgets('$name exposes key \"$key\"', (tester) async {\n"
      '    await tester.pumpWidget($harness);\n'
      '    await tester.pump();\n'
      "    expect(find.byKey(const ValueKey('${_escape(key)}')),\n"
      '        findsOneWidget);\n'
      '  });';

  String _typeTest(String name, String type, String harness, String label) =>
      "  // Heuristic: the source declares this $label type.\n"
      "  testWidgets('$name shows a $type $label', (tester) async {\n"
      '    await tester.pumpWidget($harness);\n'
      '    await tester.pump();\n'
      '    expect(find.byType($type), findsWidgets);\n'
      '  });';

  String _asyncTest(String name, String harness) =>
      "  // Heuristic: async widgets may resolve after the first pump; this\n"
      "  // tolerates both pending and resolved states.\n"
      "  testWidgets('$name renders through its async states without crashing',\n"
      '      (tester) async {\n'
      '    await tester.pumpWidget($harness);\n'
      '    await tester.pump();\n'
      '    await tester.pump(const Duration(milliseconds: 100));\n'
      '    expect(tester.takeException(), isNull);\n'
      '  });';

  String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}
