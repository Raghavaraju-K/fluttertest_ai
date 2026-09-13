import '../project/models.dart';

class _Rule {
  const _Rule(
    this.framework, {
    this.dependencies = const [],
    this.importPackages = const [],
    this.classIdentifiers = const [],
  });
  final StateManagement framework;
  final List<String> dependencies;
  final List<String> importPackages;
  final List<String> classIdentifiers;
}

/// Rules are ordered by priority; the highest weighted score wins.
const _rules = <_Rule>[
  _Rule(
    StateManagement.riverpod,
    dependencies: ['flutter_riverpod', 'riverpod', 'hooks_riverpod'],
    importPackages: ['flutter_riverpod', 'riverpod', 'hooks_riverpod'],
    classIdentifiers: [
      'ConsumerWidget',
      'ConsumerStatefulWidget',
      'HookConsumerWidget',
      'StateNotifier',
      'AsyncNotifier',
    ],
  ),
  _Rule(
    StateManagement.bloc,
    dependencies: ['flutter_bloc', 'bloc', 'bloc_concurrency'],
    importPackages: ['flutter_bloc', 'bloc'],
    classIdentifiers: [
      'Bloc',
      'Cubit',
      'BlocProvider',
      'BlocBuilder',
      'BlocConsumer',
      'BlocListener',
    ],
  ),
  _Rule(
    StateManagement.provider,
    dependencies: ['provider'],
    importPackages: ['provider'],
    classIdentifiers: [
      'ChangeNotifier',
      'ChangeNotifierProvider',
      'MultiProvider',
      'ProxyProvider',
    ],
  ),
  _Rule(
    StateManagement.getx,
    dependencies: ['get', 'getx'],
    importPackages: ['get', 'getx'],
    classIdentifiers: [
      'GetxController',
      'GetView',
      'GetMaterialApp',
      'GetBuilder',
      'Obx',
    ],
  ),
  _Rule(
    StateManagement.mobx,
    dependencies: ['mobx', 'flutter_mobx'],
    importPackages: ['mobx', 'flutter_mobx'],
    classIdentifiers: ['Observable', 'Observer', 'Computed', 'Action'],
  ),
  _Rule(
    StateManagement.redux,
    dependencies: ['redux', 'flutter_redux'],
    importPackages: ['redux', 'flutter_redux'],
    classIdentifiers: ['Store', 'StoreConnector', 'StoreProvider'],
  ),
  _Rule(
    StateManagement.signals,
    dependencies: ['signals', 'signals_flutter'],
    importPackages: ['signals', 'signals_flutter'],
    classIdentifiers: ['Signal', 'SignalProvider'],
  ),
  _Rule(
    StateManagement.valueNotifier,
    classIdentifiers: ['ValueNotifier', 'ValueListenableBuilder'],
  ),
];

/// Detects the project's state-management approach from pubspec dependencies,
/// import URIs, class inheritance, and widget usage.
///
/// Every result carries evidence and a confidence score. Matches are exact:
/// dependency names must match exactly, import URIs must start with the
/// package prefix, and identifiers must match whole class or creation names,
/// so unrelated packages containing substrings like `get` never cause false
/// positives.
class StateManagementDetector {
  StateManagementResult detect(
      Map<String, dynamic> pubspec, List<DartFileInfo> files) {
    final dependencies = <String>{
      for (final map in [pubspec['dependencies'], pubspec['dev_dependencies']])
        ...?((map as Map?)?.keys.map((key) => key.toString().toLowerCase())),
    };
    final imports = files.expand((f) => f.imports).toSet();
    final superclasses = <String, String>{
      for (final file in files)
        for (final classInfo in file.classDetails)
          if (classInfo.superclassName.isNotEmpty)
            classInfo.superclassName: classInfo.name,
    };
    final creationNames = files.expand((f) => f.creationNames).toSet();

    var bestFramework = StateManagement.unknown;
    var bestScore = 0.0;
    var bestEvidence = const <Evidence>[];

    for (final rule in _rules) {
      final evidence = <Evidence>[];
      var score = 0.0;
      for (final dependency in rule.dependencies) {
        if (dependencies.contains(dependency)) {
          evidence.add(Evidence('dependency', 'pubspec: $dependency'));
          score += 0.9;
        }
      }
      for (final package in rule.importPackages) {
        if (imports.any((uri) => uri.startsWith('package:$package/'))) {
          evidence.add(Evidence('import', 'package:$package/...'));
          score += 0.7;
        }
      }
      for (final identifier in rule.classIdentifiers) {
        final owner = superclasses[identifier];
        if (owner != null) {
          evidence
              .add(Evidence('class inheritance', '$owner extends $identifier'));
          score += 0.85;
          break;
        }
        if (creationNames.contains(identifier)) {
          evidence
              .add(Evidence('widget usage', '$identifier used in widget code'));
          score += 0.6;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestFramework = rule.framework;
        bestEvidence = evidence;
      }
    }

    // Flutter's built-in setState: a self-contained approach. It outranks
    // weak, usage-only library evidence but loses to a real dependency match.
    if (files.any((f) => f.usesSetState) && bestScore <= 0.8) {
      bestFramework = StateManagement.setState;
      bestScore = 0.8;
      bestEvidence = const [
        Evidence('widget usage', 'setState(() { ... }) inside a State class'),
      ];
    }

    if (bestScore <= 0) {
      if (files.any((f) => f.isWidget)) {
        return StateManagementResult(
          framework: StateManagement.unknown,
          confidence: 0.25,
          evidence: const [
            Evidence(
                'absence',
                'Flutter widgets found but no known state-management '
                    'evidence; conservative behavior-based fallback applies'),
          ],
          adapter: 'genericAdapter',
        );
      }
      return const StateManagementResult(
        framework: StateManagement.unknown,
        confidence: 0.0,
        evidence: [Evidence('absence', 'No known state-management evidence')],
        adapter: 'genericAdapter',
      );
    }

    return StateManagementResult(
      framework: bestFramework,
      confidence: bestScore.clamp(0.0, 0.98).toDouble(),
      evidence: bestEvidence,
      adapter: _adapterFor(bestFramework),
    );
  }

  String _adapterFor(StateManagement framework) => switch (framework) {
        StateManagement.riverpod => 'riverpodAdapter',
        StateManagement.bloc => 'blocAdapter',
        StateManagement.provider => 'providerAdapter',
        StateManagement.getx => 'getxAdapter',
        StateManagement.redux => 'reduxAdapter',
        StateManagement.mobx => 'mobxAdapter',
        StateManagement.valueNotifier => 'valueNotifierAdapter',
        StateManagement.setState => 'setStateAdapter',
        StateManagement.signals => 'genericAdapter',
        StateManagement.unknown => 'genericAdapter',
      };
}
