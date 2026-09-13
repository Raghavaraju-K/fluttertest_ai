import 'package:test/test.dart';

import 'package:fluttertest_ai/fluttertest_ai.dart';

DartFileInfo _file({
  String path = 'lib/main.dart',
  List<String> imports = const [],
  List<ClassInfo> classDetails = const [],
  List<String> creationNames = const [],
  bool usesSetState = false,
  bool isWidget = false,
}) {
  return DartFileInfo(
    path: path,
    isWidget: isWidget,
    isLogic: !isWidget,
    classes: [for (final c in classDetails) c.name],
    functions: const [],
    imports: imports,
    visibleTexts: const [],
    hasMaterial: false,
    hasCupertino: false,
    classDetails: classDetails,
    topLevelFunctions: const [],
    creationNames: creationNames,
    keys: const [],
    buttonTypes: const [],
    hasTextField: false,
    textFieldTypes: const [],
    hasForm: false,
    hasFormValidator: false,
    loadingIndicators: const [],
    hasAsyncBuilder: false,
    consumesInheritedState: false,
    usesSetState: usesSetState,
    routeNames: const [],
  );
}

ClassInfo _class(
  String name,
  String superclassName, {
  String? widgetSuperkind,
  bool isChangeNotifier = false,
  bool isCubit = false,
  bool isBloc = false,
  bool isStateNotifier = false,
}) {
  return ClassInfo(
    name: name,
    superclassName: superclassName,
    isAbstract: false,
    widgetSuperkind: widgetSuperkind,
    constructors: const [],
    methods: const [],
    isChangeNotifier: isChangeNotifier,
    isCubit: isCubit,
    isBloc: isBloc,
    isStateNotifier: isStateNotifier,
    hasFromJsonFactory: false,
  );
}

Map<String, dynamic> _pubspec(List<String> dependencies) => {
      'dependencies': {for (final d in dependencies) d: 'any'},
    };

void main() {
  final detector = StateManagementDetector();

  group('import matching is package-exact, not substring', () {
    test('the GetX token "get" does not match package:flutter/widgets.dart',
        () {
      final files = [
        _file(
          isWidget: true,
          imports: const ['package:flutter/widgets.dart'],
          classDetails: [_class('MyWidget', 'StatelessWidget')],
        ),
      ];
      final result = detector.detect(_pubspec(const ['flutter']), files);
      expect(result.framework, isNot(StateManagement.getx));
      expect(
        result.evidence
            .any((e) => e.kind == 'import' && e.value.contains('get')),
        isFalse,
      );
    });
  });

  group('setState requires real evidence', () {
    test('a StatelessWidget-only project with no setState resolves to unknown',
        () {
      final files = [
        _file(
          isWidget: true,
          imports: const ['package:flutter/material.dart'],
          classDetails: [_class('CustomScreen', 'StatelessWidget')],
          usesSetState: false,
        ),
      ];
      final result = detector.detect(_pubspec(const ['flutter']), files);
      expect(result.framework, StateManagement.unknown);
      expect(result.adapter, 'genericAdapter');
    });

    test('a project that genuinely calls setState resolves to setState', () {
      final files = [
        _file(
          isWidget: true,
          imports: const ['package:flutter/material.dart'],
          classDetails: [_class('_CounterState', 'State')],
          usesSetState: true,
        ),
      ];
      final result = detector.detect(_pubspec(const ['flutter']), files);
      expect(result.framework, StateManagement.setState);
      expect(result.adapter, 'setStateAdapter');
      expect(
        result.evidence.any((e) => e.value.contains('setState')),
        isTrue,
        reason: 'usesSetState must be cited as evidence',
      );
    });
  });

  group('framework detection from declared dependency', () {
    test('Riverpod detects with non-empty evidence and correct adapter', () {
      final files = [
        _file(imports: const ['package:flutter/material.dart']),
      ];
      final result =
          detector.detect(_pubspec(const ['flutter_riverpod']), files);
      expect(result.framework, StateManagement.riverpod);
      expect(result.adapter, 'riverpodAdapter');
      expect(result.evidence, isNotEmpty);
      expect(result.confidence, greaterThan(0));
    });

    test('Provider detects with non-empty evidence and correct adapter', () {
      final files = [
        _file(imports: const ['package:flutter/material.dart']),
      ];
      final result = detector.detect(_pubspec(const ['provider']), files);
      expect(result.framework, StateManagement.provider);
      expect(result.adapter, 'providerAdapter');
      expect(result.evidence, isNotEmpty);
      expect(result.confidence, greaterThan(0));
    });

    test('BLoC detects with non-empty evidence and correct adapter', () {
      final files = [
        _file(imports: const ['package:flutter/material.dart']),
      ];
      final result = detector.detect(_pubspec(const ['flutter_bloc']), files);
      expect(result.framework, StateManagement.bloc);
      expect(result.adapter, 'blocAdapter');
      expect(result.evidence, isNotEmpty);
      expect(result.confidence, greaterThan(0));
    });
  });

  group('precedence between competing evidence', () {
    test(
        'a declared dependency outweighs an incidental ChangeNotifier class '
        'from another framework', () {
      // Mirrors the riverpod_async fixture: flutter_riverpod is declared,
      // but the only state class extends the (Flutter-core) ChangeNotifier
      // rather than any Riverpod-specific base class.
      final files = [
        _file(
          imports: const ['package:flutter/foundation.dart'],
          classDetails: [_class('UserModelNotifier', 'ChangeNotifier')],
        ),
      ];
      final result =
          detector.detect(_pubspec(const ['flutter_riverpod']), files);
      expect(result.framework, StateManagement.riverpod);
    });
  });
}
