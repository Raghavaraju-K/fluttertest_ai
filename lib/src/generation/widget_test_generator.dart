import '../adapters/state_management_adapter.dart';
import '../analysis/widget_analyzer.dart';
import '../project/dart_symbols.dart';
import '../project/models.dart';
import '../project/plan_models.dart';
import '../templates/templates.dart';

/// Generates conservative but behaviourally meaningful widget tests from the
/// already-computed [DartFileInfo] analysis attached to [ProjectAnalysis] —
/// it never re-parses source itself.
///
/// One `testWidgets` block is emitted per observable behaviour: static UI
/// text, stable keys, button/text-field presence, loading indicators, and
/// (when unambiguous) simple input/tap/submit interactions. Only stable
/// selectors (keys, text, types) are used — never widget-tree indexes.
///
/// Widgets whose unnamed constructor has unsynthesizable required
/// parameters, or that read inherited state unsafely for their detected
/// state-management framework (see [WidgetAnalyzer.requiresUnsafeState]),
/// are skipped with an explanatory note rather than guessed at.
class WidgetTestGenerator {
  WidgetTestGenerator({WidgetAnalyzer? widgetAnalyzer})
      : _widgetAnalyzer = widgetAnalyzer ?? WidgetAnalyzer();
  final WidgetAnalyzer _widgetAnalyzer;

  /// Static UI-text assertions are capped so tests stay focused on the
  /// signals most likely to matter, rather than asserting every string.
  static const int _maxTextAssertions = 5;

  static const List<String> _fieldNameHints = [
    'field',
    'input',
    'email',
    'search',
    'form',
    'text',
  ];
  static const List<String> _buttonNameHints = [
    'button',
    'btn',
    'submit',
    'tap',
  ];

  GenerationOutcome generate(TestPlanItem item, ProjectAnalysis analysis) {
    final file = _fileFor(item, analysis);
    if (file == null) {
      return GenerationOutcome(null,
          notes: ['analysis data for ${item.source} not found']);
    }
    final widgetClasses = file.classDetails.where((c) => c.isWidget).toList();
    if (widgetClasses.isEmpty) {
      return const GenerationOutcome(null, notes: ['no widget class found']);
    }

    final framework = analysis.stateManagement.framework;
    final adapter = StateManagementAdapters.forFramework(framework);
    final missingDependency = _missingAdapterDependency(adapter, analysis);
    if (missingDependency != null) {
      return GenerationOutcome(null, notes: [
        'widget harness requires package $missingDependency which is not a '
            'declared dependency; FlutterTest AI never modifies pubspec.yaml, '
            'so widget tests for this file were skipped',
      ]);
    }

    final appType =
        file.hasCupertino && !file.hasMaterial ? 'CupertinoApp' : 'MaterialApp';
    final notes = <String>[];
    final blocks = <String>[];
    for (final widget in widgetClasses) {
      if (!widget.isPubliclyConstructible) {
        notes.add('${widget.name}: has required constructor parameters that '
            'cannot be safely synthesised; skipped');
        continue;
      }
      if (_widgetAnalyzer.requiresUnsafeState(widget, file, framework)) {
        notes.add('${widget.name}: reads inherited state (context.watch / '
            'context.read) that requires ${framework.label} setup this tool '
            'cannot safely construct; skipped');
        continue;
      }
      final pumpExpr = adapter.wrapHarness('$appType(home: ${widget.name}())');
      blocks.addAll(_testsForWidget(widget, file, pumpExpr, notes));
    }

    if (blocks.isEmpty) {
      return GenerationOutcome(null,
          notes:
              notes.isEmpty ? const ['no constructible widget found'] : notes);
    }

    final imports = <String>[
      file.hasCupertino && !file.hasMaterial
          ? "import 'package:flutter/cupertino.dart';"
          : "import 'package:flutter/material.dart';",
      "import 'package:flutter_test/flutter_test.dart';",
      ...adapter.extraImports,
      "import '${packageImport(file.path, analysis.root, analysis.projectName)}';",
    ].join('\n');

    final content = '${generatedFileHeader(item.confidence)}'
        '$imports\n\n'
        'void main() {\n'
        '${blocks.join('\n\n')}\n'
        '}\n'
        '// $generatedRegionEnd\n';
    return GenerationOutcome(content, notes: notes);
  }

  DartFileInfo? _fileFor(TestPlanItem item, ProjectAnalysis analysis) {
    for (final file in analysis.files) {
      if (file.path == item.source) return file;
    }
    return null;
  }

  /// Returns the first required package (extracted from an adapter's extra
  /// imports) that is not declared in the target project's dependencies, or
  /// `null` when every required package is already available.
  String? _missingAdapterDependency(
      StateManagementAdapter adapter, ProjectAnalysis analysis) {
    final pattern = RegExp(r'package:([^/]+)/');
    for (final import in adapter.extraImports) {
      final package = pattern.firstMatch(import)?.group(1);
      if (package != null && !analysis.dependencies.contains(package)) {
        return package;
      }
    }
    return null;
  }

  List<String> _testsForWidget(
    ClassInfo widget,
    DartFileInfo file,
    String pumpExpr,
    List<String> notes,
  ) {
    final name = widget.name;
    final blocks = <String>[
      '  testWidgets(\'$name renders without crashing\', (tester) async {\n'
          '    await tester.pumpWidget($pumpExpr);\n'
          '    await tester.pump();\n'
          '    expect(find.byType($name), findsOneWidget);\n'
          '  });',
    ];

    // [DartFileInfo.visibleTexts] already holds only resolved constant
    // string values (see DartSourceAnalyzer), so no dynamic/interpolated
    // text ever reaches this list — no extra filtering needed here.
    final texts = _staticTexts(file);
    if (texts.isNotEmpty) {
      // findsWidgets (>=1), not findsOneWidget: the same static text can
      // legitimately appear more than once (e.g. an AppBar title and a
      // button sharing a label), and this tool has no way to disambiguate
      // occurrences from the aggregate analysis data alone.
      final expects = texts
          .map((t) => "    expect(find.text('${_escape(t)}'), findsWidgets);")
          .join('\n');
      blocks.add(
          '  testWidgets(\'$name shows expected UI text\', (tester) async {\n'
          '    await tester.pumpWidget($pumpExpr);\n'
          '    await tester.pump();\n'
          '$expects\n'
          '  });');
    }

    if (file.keys.isNotEmpty) {
      final distinctKeys = {...file.keys}.toList();
      final expects = distinctKeys
          .map((k) =>
              "    expect(find.byKey(const ValueKey('${_escape(k)}')), findsOneWidget);")
          .join('\n');
      blocks.add(
          '  testWidgets(\'$name exposes its stable keys\', (tester) async {\n'
          '    await tester.pumpWidget($pumpExpr);\n'
          '    await tester.pump();\n'
          '$expects\n'
          '  });');
    }

    if (file.buttonTypes.isNotEmpty) {
      final distinctButtons = {...file.buttonTypes}.toList();
      final expects = distinctButtons
          .map((b) => '    expect(find.byType($b), findsWidgets);')
          .join('\n');
      blocks
          .add('  testWidgets(\'$name renders its buttons\', (tester) async {\n'
              '    await tester.pumpWidget($pumpExpr);\n'
              '    await tester.pump();\n'
              '$expects\n'
              '  });');
    }

    if (file.hasTextField) {
      final distinctFieldTypes = {...file.textFieldTypes}.toList();
      if (distinctFieldTypes.isNotEmpty) {
        final expects = distinctFieldTypes
            .map((t) => '    expect(find.byType($t), findsWidgets);')
            .join('\n');
        blocks.add(
            '  testWidgets(\'$name renders its text field\', (tester) async {\n'
            '    await tester.pumpWidget($pumpExpr);\n'
            '    await tester.pump();\n'
            '$expects\n'
            '  });');
      }
      final fieldKey = _fieldKey(file);
      if (fieldKey != null) {
        blocks.add('  testWidgets(\'$name accepts input in the text field\', '
            '(tester) async {\n'
            '    await tester.pumpWidget($pumpExpr);\n'
            '    await tester.pump();\n'
            "    await tester.enterText(find.byKey(const ValueKey('${_escape(fieldKey)}')), 'test input');\n"
            '    await tester.pump();\n'
            "    expect(find.text('test input'), findsOneWidget);\n"
            '  });');
      } else {
        notes.add('$name: has a text field but no key can be unambiguously '
            'matched to it; skipped the input-entry test');
      }
    }

    final buttonKey = _buttonKey(file);
    if (buttonKey != null) {
      blocks.add(
          '  testWidgets(\'$name still renders after tapping the button\', '
          '(tester) async {\n'
          '    await tester.pumpWidget($pumpExpr);\n'
          '    await tester.pump();\n'
          '    // Heuristic: only asserts the widget still renders after the tap;\n'
          '    // this tool cannot safely infer what state change the tap should\n'
          '    // cause.\n'
          "    await tester.tap(find.byKey(const ValueKey('${_escape(buttonKey)}')));\n"
          '    await tester.pumpAndSettle();\n'
          '    expect(find.byType($name), findsOneWidget);\n'
          '  });');
    } else if (file.buttonTypes.isNotEmpty) {
      notes.add('$name: has button(s) but none has a key that can be '
          'unambiguously targeted; skipped the tap test');
    }

    if (file.hasForm || file.hasFormValidator) {
      final fieldKey = _fieldKey(file);
      final submitSelector = _submitButtonSelector(file);
      if (fieldKey != null && submitSelector != null) {
        blocks.add('  testWidgets(\'$name submits the form without crashing\', '
            '(tester) async {\n'
            '    await tester.pumpWidget($pumpExpr);\n'
            '    await tester.pump();\n'
            "    await tester.enterText(find.byKey(const ValueKey('${_escape(fieldKey)}')), 'sample value');\n"
            '    await tester.pump();\n'
            '    // Heuristic: exercises the submit path without asserting\n'
            '    // validation outcomes, since those depend on validator logic\n'
            '    // this tool does not execute.\n'
            '    await tester.tap($submitSelector);\n'
            '    await tester.pumpAndSettle();\n'
            '    expect(find.byType($name), findsOneWidget);\n'
            '  });');
      } else {
        notes.add('$name: has a form but no unambiguous field key and submit '
            'button pair; skipped the form-submission test');
      }
    }

    if (file.loadingIndicators.isNotEmpty) {
      final distinctIndicators = {...file.loadingIndicators}.toList();
      final expects = distinctIndicators
          .map((t) => '    expect(find.byType($t), findsWidgets);')
          .join('\n');
      blocks.add(
          '  testWidgets(\'$name renders a loading indicator\', (tester) async {\n'
          '    await tester.pumpWidget($pumpExpr);\n'
          '    // Heuristic: pumps once instead of pumpAndSettle, since a\n'
          '    // progress indicator\'s animation may never settle.\n'
          '    await tester.pump();\n'
          '$expects\n'
          '  });');
    } else if (file.hasAsyncBuilder) {
      notes.add('$name: uses FutureBuilder/StreamBuilder but no concrete '
          'loading indicator type was found; skipped the loading-state test');
    }

    return blocks;
  }

  List<String> _staticTexts(DartFileInfo file) {
    final seen = <String>{};
    final result = <String>[];
    for (final text in file.visibleTexts) {
      if (!seen.add(text)) continue;
      result.add(text);
      if (result.length >= _maxTextAssertions) break;
    }
    return result;
  }

  /// Keys are captured file-wide, with no record of which widget owns each
  /// one, so ownership is inferred conservatively: a key whose name hints at
  /// a field role (and not a button role) is used unambiguously; otherwise a
  /// single leftover key is used only when no other keyed role could claim
  /// it.
  String? _fieldKey(DartFileInfo file) {
    if (!file.hasTextField || file.keys.isEmpty) return null;
    final named = file.keys.where((k) {
      final lower = k.toLowerCase();
      return _fieldNameHints.any(lower.contains) &&
          !_buttonNameHints.any(lower.contains);
    }).toSet();
    if (named.length == 1) return named.first;
    if (file.keys.length == 1 && file.buttonTypes.isEmpty) {
      return file.keys.first;
    }
    return null;
  }

  String? _buttonKey(DartFileInfo file) {
    if (file.buttonTypes.isEmpty || file.keys.isEmpty) return null;
    final named = file.keys.where((k) {
      final lower = k.toLowerCase();
      return _buttonNameHints.any(lower.contains) &&
          !_fieldNameHints.any(lower.contains);
    }).toSet();
    if (named.length == 1) return named.first;
    if (file.keys.length == 1 && !file.hasTextField) return file.keys.first;
    return null;
  }

  /// Identifies a submit button either by a stable key, or — when there is
  /// exactly one button type and exactly one static visible text — by the
  /// stable type+text combination, e.g. `find.widgetWithText(ElevatedButton,
  /// 'Register')`. Returns `null` when neither is unambiguous.
  String? _submitButtonSelector(DartFileInfo file) {
    final buttonKey = _buttonKey(file);
    if (buttonKey != null) {
      return "find.byKey(const ValueKey('${_escape(buttonKey)}'))";
    }
    final distinctButtons = {...file.buttonTypes}.toList();
    if (distinctButtons.length != 1) return null;
    final texts = _staticTexts(file);
    if (texts.length != 1) return null;
    return "find.widgetWithText(${distinctButtons.first}, '${_escape(texts.first)}')";
  }

  String _escape(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
}
