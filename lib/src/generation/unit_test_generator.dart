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
        if (!method.isStatic ||
            method.isOperator ||
            method.isAsynchronous ||
            method.isSetter) {
          continue;
        }
        final target = '${clazz.name}.${method.name}';
        if (method.isGetter) {
          groups.add(_getterTest(target, method.returnTypeSource));
          continue;
        }
        addGroup(_callableTests(target, method), target);
      }
    }
    for (final clazz in _logic.pureMethodClasses(file)) {
      for (final method in clazz.methods) {
        if (method.isStatic ||
            method.isOperator ||
            method.isAsynchronous ||
            method.isSetter) {
          continue;
        }
        final target = '${clazz.name}().${method.name}';
        if (method.isGetter) {
          groups.add(_getterTest(target, method.returnTypeSource));
          continue;
        }
        addGroup(_callableTests(target, method), target);
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
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import '$import';\n\n"
        'void main() {\n'
        '${groups.take(12).join('\n\n')}\n'
        '}\n'
        '// $generatedRegionEnd\n';
    return GenerationOutcome(content, notes: notes);
  }

  /// Return types safe to assert with `isA<T>()` without risking a
  /// non-compiling generic or a false assumption about async semantics.
  static const Set<String> _knownSafeReturnTypes = {
    'bool',
    'int',
    'double',
    'num',
    'String',
    'bool?',
    'int?',
    'double?',
    'num?',
    'String?',
  };

  /// Returns the return type to assert with `isA<T>()`, or `null` when the
  /// type is unknown, `void`, `dynamic`, or asynchronous — in which case the
  /// caller falls back to a `returnsNormally` no-throw check.
  String? _typeAssertion(String returnTypeSource) {
    final type = returnTypeSource.trim();
    return _knownSafeReturnTypes.contains(type) ? type : null;
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
    List<String>? nullable;
    if (function.hasNullableParameter) {
      nullable = <String>[
        for (var i = 0; i < required.length; i++)
          required[i].isNullable ? 'null' : typical[i],
      ];
    }

    // Collapse cases that produce byte-identical calls (e.g. a zero-argument
    // method has no distinct "typical" vs "empty" input, and a single
    // nullable parameter's "empty" and "null" representations often
    // coincide) so no two emitted tests share the same body.
    final seenArgs = <String>{};
    final cases = <_ArgCase>[];
    void addCase(List<String> args, _ArgKind kind) {
      if (!seenArgs.add(args.join('\u0000'))) return;
      cases.add(_ArgCase(args, kind));
    }

    addCase(typical, _ArgKind.typical);
    addCase(empty, _ArgKind.empty);
    if (nullable != null) addCase(nullable, _ArgKind.nullable);

    final typeAssertion = _typeAssertion(function.returnTypeSource);
    return cases
        .map((c) => _callTest(target, c.args, c.kind, typeAssertion))
        .join('\n\n');
  }

  String _getterTest(String target, String returnTypeSource) {
    final typeAssertion = _typeAssertion(returnTypeSource);
    if (typeAssertion == null) {
      return '  // Heuristic: a getter has no parameter list; this only checks\n'
          '  // that reading it does not throw.\n'
          "  test('$target can be read', () {\n"
          '    expect(() => $target, returnsNormally);\n'
          '  });';
    }
    return '  // Heuristic: a getter has no parameter list; this only checks\n'
        '  // that reading it does not throw and yields the declared type.\n'
        "  test('$target returns a $typeAssertion', () {\n"
        '    expect($target, isA<$typeAssertion>());\n'
        '  });';
  }

  String _labelFor(List<String> args, _ArgKind kind, String? typeAssertion) {
    if (args.isEmpty) {
      return typeAssertion == null ? 'is called' : 'returns a $typeAssertion';
    }
    if (kind == _ArgKind.nullable || args.contains('null')) {
      return 'handles null input';
    }
    final suffix = kind == _ArgKind.typical ? 'typical input' : 'empty input';
    return typeAssertion == null
        ? 'accepts $suffix'
        : 'returns a $typeAssertion for $suffix';
  }

  String _callTest(
      String target, List<String> args, _ArgKind kind, String? typeAssertion) {
    final label = _labelFor(args, kind, typeAssertion);
    final call = '$target(${args.join(', ')})';
    if (typeAssertion == null) {
      return '  // Heuristic: asserts the call succeeds for this input.\n'
          "  test('$target $label', () {\n"
          '    expect(() => $call, returnsNormally);\n'
          '  });';
    }
    return '  // Heuristic: asserts the call succeeds for this input and\n'
        '  // returns the declared type.\n'
        "  test('$target $label', () {\n"
        '    expect($call, isA<$typeAssertion>());\n'
        '  });';
  }

  String _fromJsonTest(String className) =>
      '  // Heuristic: fromJson may legitimately reject empty data with a\n'
      '  // thrown error, or legitimately return a $className. Both are\n'
      '  // acceptable outcomes, but exactly one must actually happen — this\n'
      '  // always makes one real assertion so the test cannot pass silently.\n'
      "  test('$className.fromJson tolerates an empty map', () {\n"
      '    Object? result;\n'
      '    var threw = false;\n'
      '    try {\n'
      '      result = $className.fromJson(const <String, dynamic>{});\n'
      '    } catch (_) {\n'
      '      threw = true;\n'
      '    }\n'
      '    expect(threw || result is $className, isTrue,\n'
      "        reason: '$className.fromJson must either return a "
      "$className or throw');\n"
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

/// The provenance of a synthesized argument list, used to pick an honest
/// test name once byte-identical argument lists have been deduplicated.
enum _ArgKind { typical, empty, nullable }

class _ArgCase {
  const _ArgCase(this.args, this.kind);
  final List<String> args;
  final _ArgKind kind;
}
