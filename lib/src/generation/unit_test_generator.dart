import 'dart:io';

import '../analysis/dart_source_analyzer.dart';
import '../analysis/logic_analyzer.dart';
import '../project/dart_symbols.dart';
import '../project/models.dart';
import '../project/plan_models.dart';
import '../templates/templates.dart';
import 'value_fixtures.dart';

/// Generates conservative unit tests:
///
/// * typed top-level functions (typical, empty, and null inputs),
/// * static methods and instance methods of utility classes (validators,
///   formatters, mappers, converters, parsers, helpers, calculators),
/// * tolerant `fromJson` serialization checks,
/// * construct/dispose smoke tests for state containers (ChangeNotifier,
///   Cubit, Bloc, StateNotifier) whose dependencies are injectable, meaning
///   they have no required constructor parameters.
///
/// Asynchronous callables are deliberately skipped to avoid hidden I/O, and
/// no test asserts concrete return values — only that calls succeed.
class UnitTestGenerator {
  UnitTestGenerator({LogicAnalyzer? logic, ValueFixtures? values})
      : _logic = logic ?? LogicAnalyzer(),
        _values = values ?? ValueFixtures();
  final LogicAnalyzer _logic;
  final ValueFixtures _values;

  GenerationOutcome generate(TestPlanItem item, ProjectAnalysis analysis) {
    final file = DartSourceAnalyzer().analyze(File(item.source));
    final groups = <String>[];
    final notes = <String>[];

    void addGroup(String? group, String label) {
      if (group == null) {
        notes.add(
            '$label: parameter types are not safely synthesizable; skipped');
      } else {
        groups.add(group);
      }
    }

    for (final function in _logic.unitFunctions(file)) {
      if (function.isAsynchronous) {
        notes.add('${function.name}(): asynchronous callables are skipped '
            'to avoid hidden I/O');
        continue;
      }
      addGroup(_callableTests(function.name, function), function.name);
    }
    for (final clazz in file.classDetails.where((c) => c.isPublic)) {
      for (final method in clazz.methods) {
        if (!method.isStatic || method.isOperator || method.isAsynchronous) {
          continue;
        }
        addGroup(_callableTests('${clazz.name}.${method.name}', method),
            '${clazz.name}.${method.name}');
      }
    }
    for (final clazz in _logic.pureMethodClasses(file)) {
      for (final method in clazz.methods) {
        if (method.isStatic || method.isOperator || method.isAsynchronous) {
          continue;
        }
        addGroup(_callableTests('${clazz.name}().${method.name}', method),
            '${clazz.name}.${method.name}');
      }
    }
    for (final clazz in _logic.serializableClasses(file)) {
      if (!clazz.isPublic || clazz.isAbstract) continue;
      groups.add(_fromJsonTest(clazz.name));
    }
    for (final clazz in _logic.lifecycleClasses(file)) {
      groups.add(_lifecycleTest(clazz));
    }

    if (groups.isEmpty) {
      return GenerationOutcome(null,
          notes:
              notes.isEmpty ? ['no safely callable public API found'] : notes);
    }
    if (groups.length > 12) {
      notes.add('file produced ${groups.length} targets; capped at 12 groups');
    }
    final import =
        packageImport(item.source, analysis.root, analysis.projectName);
    final content = '${generatedFileHeader(item.confidence)}'
        "import 'package:test/test.dart';\n"
        "import '$import';\n\n"
        'void main() {\n'
        '${groups.take(12).join('\n\n')}\n'
        '}\n'
        '// $generatedRegionEnd\n';
    return GenerationOutcome(content, notes: notes);
  }

  String? _callableTests(String target, FunctionInfo function) {
    final required = function.requiredParameters;
    if (required.length > 3) return null;
    final typical = <String>[];
    for (final parameter in required) {
      final value = _values.typical(parameter);
      if (value == null) return null;
      typical.add(value);
    }
    final empty = <String>[];
    for (final parameter in required) {
      final value = _values.empty(parameter);
      if (value == null) return null;
      empty.add(value);
    }
    final tests = <String>[
      _callTest(target, typical, 'accepts typical input'),
      _callTest(target, empty, 'accepts empty input'),
    ];
    if (function.hasNullableParameter) {
      final nullableArgs = <String>[
        for (var i = 0; i < required.length; i++)
          required[i].isNullable ? 'null' : typical[i],
      ];
      tests.add(_callTest(
          target, nullableArgs, 'accepts null for nullable parameters'));
    }
    return tests.join('\n');
  }

  String _callTest(String target, List<String> args, String label) {
    final call = '$target(${args.join(', ')})';
    return '  // Heuristic: asserts the call succeeds for this input.\n'
        "  test('$target $label', () {\n"
        '    expect(() => $call, returnsNormally);\n'
        '  });';
  }

  String _fromJsonTest(String className) =>
      '  // Heuristic: fromJson may legitimately reject empty data; this only\n'
      '  // checks that a successful parse yields the expected type.\n'
      "  test('$className.fromJson tolerates an empty map', () {\n"
      '    Object? result;\n'
      '    try {\n'
      '      result = $className.fromJson(const <String, dynamic>{});\n'
      '    } catch (_) {}\n'
      '    if (result != null) {\n'
      '      expect(result, isA<$className>());\n'
      '    }\n'
      '  });';

  String _lifecycleTest(ClassInfo clazz) {
    final name = clazz.name;
    if (clazz.isChangeNotifier) {
      return '  // Heuristic: state container constructs cleanly and releases resources.\n'
          "  test('$name constructs and disposes cleanly', () {\n"
          '    final notifier = $name();\n'
          '    expect(notifier, isA<$name>());\n'
          '    notifier.dispose();\n'
          '  });';
    }
    if (clazz.isCubit || clazz.isBloc) {
      return '  // Heuristic: state container constructs cleanly and closes its stream.\n'
          "  test('$name constructs and closes cleanly', () async {\n"
          '    final container = $name();\n'
          '    expect(container, isA<$name>());\n'
          '    await container.close();\n'
          '  });';
    }
    return '  // Heuristic: state container constructs cleanly and can be released.\n'
        "  test('$name constructs and closes cleanly', () async {\n"
        '    final container = $name();\n'
        '    expect(container, isA<$name>());\n'
        '    container.dispose();\n'
        '  });';
  }
}
