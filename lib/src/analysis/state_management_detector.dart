import '../project/dart_symbols.dart';
import '../project/models.dart';

/// One rule describing how a single framework shows up in a project.
///
/// Every signal is matched exactly (package name, class name, or
/// constructor name) — never as a substring of a larger blob. That
/// distinction matters: the GetX package name `get` is also a substring of
/// `package:flutter/widgets.dart`, so naive `.contains()` matching produces
/// false positives on any Flutter project.
class _Rule {
  const _Rule({
    required this.framework,
    this.dependencyNames = const {},
    this.importPackageNames = const {},
    this.superclassMatch,
    this.creationNames = const {},
  });

  final StateManagement framework;
  final Set<String> dependencyNames;
  final Set<String> importPackageNames;
  final bool Function(ClassInfo)? superclassMatch;
  final Set<String> creationNames;
}

/// Detects the dominant state-management approach from structured,
/// tokenised evidence: declared dependencies, parsed import package names,
/// exact superclass matches, and exact widget-constructor names.
///
/// Rules are declaration-ordered from most to least specific (external
/// packages first, `setState` last) so that, when two frameworks tie on
/// confidence, the more specific/external one wins deterministically
/// instead of depending on map/hash iteration order.
class StateManagementDetector {
  static final List<_Rule> _rules = [
    _Rule(
      framework: StateManagement.riverpod,
      dependencyNames: const {'flutter_riverpod', 'riverpod', 'hooks_riverpod'},
      importPackageNames: const {
        'flutter_riverpod',
        'riverpod',
        'hooks_riverpod'
      },
      superclassMatch: (c) =>
          c.isStateNotifier ||
          const {
            'ConsumerWidget',
            'ConsumerStatefulWidget',
            'HookConsumerWidget'
          }.contains(c.superclassName),
      creationNames: const {'ProviderScope', 'Consumer'},
    ),
    _Rule(
      framework: StateManagement.bloc,
      dependencyNames: const {'flutter_bloc', 'bloc'},
      importPackageNames: const {'flutter_bloc', 'bloc'},
      superclassMatch: (c) => c.isCubit || c.isBloc,
      creationNames: const {
        'BlocProvider',
        'MultiBlocProvider',
        'BlocBuilder',
        'BlocListener',
        'BlocConsumer'
      },
    ),
    _Rule(
      framework: StateManagement.provider,
      dependencyNames: const {'provider'},
      importPackageNames: const {'provider'},
      // Exact match on `ChangeNotifier` only — not the broader
      // `isChangeNotifier` flag, which also covers `ValueNotifier` and
      // would conflate the Provider and ValueNotifier frameworks.
      superclassMatch: (c) => c.superclassName == 'ChangeNotifier',
      creationNames: const {
        'ChangeNotifierProvider',
        'MultiProvider',
        'Consumer',
        'Selector'
      },
    ),
    _Rule(
      framework: StateManagement.getx,
      dependencyNames: const {'get', 'getx'},
      importPackageNames: const {'get', 'getx'},
      superclassMatch: (c) =>
          const {'GetView', 'GetxController'}.contains(c.superclassName),
      creationNames: const {'GetBuilder', 'GetX', 'Obx', 'GetMaterialApp'},
    ),
    _Rule(
      framework: StateManagement.redux,
      dependencyNames: const {'flutter_redux', 'redux', 'async_redux'},
      importPackageNames: const {'flutter_redux', 'redux', 'async_redux'},
      creationNames: const {'StoreConnector', 'StoreProvider'},
    ),
    _Rule(
      framework: StateManagement.mobx,
      dependencyNames: const {'flutter_mobx', 'mobx'},
      importPackageNames: const {'flutter_mobx', 'mobx'},
      creationNames: const {'Observer'},
    ),
    _Rule(
      framework: StateManagement.signals,
      dependencyNames: const {'signals', 'signals_flutter'},
      importPackageNames: const {'signals', 'signals_flutter'},
    ),
    _Rule(
      framework: StateManagement.valueNotifier,
      // ValueNotifier ships in Flutter's own foundation library, so there
      // is no dependency/import to key off — only exact class usage.
      superclassMatch: (c) => c.superclassName == 'ValueNotifier',
      creationNames: const {'ValueListenableBuilder'},
    ),
  ];

  StateManagementResult detect(
      Map<String, dynamic> pubspec, List<DartFileInfo> files) {
    final deps = _dependencyNames(pubspec);
    final importPackages = <String>{
      for (final f in files)
        for (final uri in f.imports)
          if (_packageNameOf(uri) case final pkg?) pkg,
    };
    final classes = files.expand((f) => f.classDetails).toList();
    final creationNames = <String>{for (final f in files) ...f.creationNames};

    final candidates = <StateManagementResult>[
      for (final rule in _rules)
        _evaluate(rule, deps, importPackages, classes, creationNames),
      _evaluateSetState(classes, files),
    ].where((r) => r.evidence.isNotEmpty).toList();

    if (candidates.isEmpty) {
      return const StateManagementResult(
        framework: StateManagement.unknown,
        confidence: 0,
        evidence: [Evidence('absence', 'No known state-management evidence')],
        adapter: 'genericAdapter',
      );
    }

    // Highest confidence wins; on an exact tie the first candidate in
    // `candidates` order (i.e. `_rules` declaration order, setState last)
    // is kept. `List.sort` is not guaranteed stable, so ties are resolved
    // manually here rather than by sorting.
    var best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.confidence > best.confidence) best = candidate;
    }
    return best;
  }

  Set<String> _dependencyNames(Map<String, dynamic> pubspec) => {
        ...((pubspec['dependencies'] as Map? ?? const {})
            .keys
            .map((e) => e.toString().toLowerCase())),
        ...((pubspec['dev_dependencies'] as Map? ?? const {})
            .keys
            .map((e) => e.toString().toLowerCase())),
      };

  /// Extracts the exact package name segment from a `package:` import URI
  /// (e.g. `flutter` from `package:flutter/widgets.dart`). Returns `null`
  /// for non-`package:` imports (relative or `dart:` imports) so those can
  /// never accidentally match a package-name token.
  String? _packageNameOf(String uri) {
    const prefix = 'package:';
    if (!uri.startsWith(prefix)) return null;
    final rest = uri.substring(prefix.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return null;
    return rest.substring(0, slash).toLowerCase();
  }

  StateManagementResult _evaluate(
    _Rule rule,
    Set<String> deps,
    Set<String> importPackages,
    List<ClassInfo> classes,
    Set<String> creationNames,
  ) {
    final evidence = <Evidence>[];
    for (final dep in rule.dependencyNames) {
      if (deps.contains(dep)) evidence.add(Evidence('dependency', dep));
    }
    for (final pkg in rule.importPackageNames) {
      if (importPackages.contains(pkg)) {
        evidence.add(Evidence('import', 'package:$pkg'));
      }
    }
    final superclassMatch = rule.superclassMatch;
    if (superclassMatch != null) {
      for (final c in classes) {
        if (superclassMatch(c)) {
          evidence.add(Evidence(
              'class inheritance', '${c.name} extends ${c.superclassName}'));
        }
      }
    }
    for (final name in rule.creationNames) {
      if (creationNames.contains(name)) {
        evidence.add(Evidence('widget usage', name));
      }
    }
    return StateManagementResult(
      framework: rule.framework,
      confidence: _confidence(evidence),
      evidence: evidence,
      adapter: '${rule.framework.name}Adapter',
    );
  }

  /// `setState` is only real evidence when a file actually calls it, or
  /// declares a `State<T>` subclass — never merely "a widget exists
  /// somewhere in this project", which used to misclassify pure
  /// `StatelessWidget`-only projects as `setState`.
  StateManagementResult _evaluateSetState(
      List<ClassInfo> classes, List<DartFileInfo> files) {
    final evidence = <Evidence>[];
    final setStateFileCount = files.where((f) => f.usesSetState).length;
    if (setStateFileCount > 0) {
      evidence.add(Evidence(
          'behavior', 'setState() called in $setStateFileCount file(s)'));
    }
    for (final c in classes) {
      if (c.superclassName == 'State') {
        evidence.add(Evidence('class inheritance', '${c.name} extends State'));
      }
    }
    return StateManagementResult(
      framework: StateManagement.setState,
      confidence: _confidence(evidence),
      evidence: evidence,
      adapter: 'setStateAdapter',
    );
  }

  /// Confidence scales with the strength and diversity of independent
  /// signals: each distinct evidence *kind* contributes its own weight, and
  /// additional evidence within the same kind adds a smaller diminishing
  /// bonus (extra corroboration matters, but shouldn't let e.g. five widget
  /// usages outweigh a real dependency declaration).
  double _confidence(List<Evidence> evidence) {
    if (evidence.isEmpty) return 0;
    const kindWeight = {
      'dependency': 0.5,
      'class inheritance': 0.4,
      'behavior': 0.45,
      'widget usage': 0.3,
      'import': 0.3,
    };
    final countByKind = <String, int>{};
    for (final e in evidence) {
      countByKind[e.kind] = (countByKind[e.kind] ?? 0) + 1;
    }
    var score = 0.0;
    for (final entry in countByKind.entries) {
      final weight = kindWeight[entry.key] ?? 0.2;
      score += weight + (entry.value - 1) * 0.05;
    }
    return score.clamp(0.0, 1.0);
  }
}
