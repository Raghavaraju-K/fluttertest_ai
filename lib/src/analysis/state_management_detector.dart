import '../project/models.dart';

class StateManagementDetector {
  StateManagementResult detect(
      Map<String, dynamic> pubspec, List<DartFileInfo> files) {
    final deps = <String>{
      ...((pubspec['dependencies'] as Map? ?? const {})
          .keys
          .map((e) => e.toString().toLowerCase())),
      ...((pubspec['dev_dependencies'] as Map? ?? const {})
          .keys
          .map((e) => e.toString().toLowerCase())),
    };
    final imports = files.expand((f) => f.imports).join(' ').toLowerCase();
    final sourceNames = files.expand((f) => f.classes).join(' ');
    const rules = <StateManagement, List<String>>{
      StateManagement.riverpod: [
        'flutter_riverpod',
        'riverpod',
        'providerScope',
        'ConsumerWidget'
      ],
      StateManagement.bloc: ['flutter_bloc', 'bloc', 'Cubit', 'BlocProvider'],
      StateManagement.provider: [
        'provider',
        'ChangeNotifier',
        'ChangeNotifierProvider'
      ],
      StateManagement.getx: ['get', 'getx', 'GetView'],
      StateManagement.redux: ['flutter_redux', 'redux', 'StoreConnector'],
      StateManagement.mobx: ['flutter_mobx', 'mobx', 'Observer'],
      StateManagement.signals: ['signals', 'signals_flutter'],
      StateManagement.valueNotifier: [
        'ValueNotifier',
        'ValueListenableBuilder'
      ],
    };
    for (final entry in rules.entries) {
      final hits = <Evidence>[];
      for (final token in entry.value) {
        final lower = token.toLowerCase();
        if (deps.contains(lower)) hits.add(Evidence('dependency', token));
        if (imports.contains(lower)) hits.add(Evidence('import', token));
        if (sourceNames.toLowerCase().contains(lower)) {
          hits.add(Evidence('class/widget usage', token));
        }
      }
      if (hits.isNotEmpty) {
        return StateManagementResult(
            framework: entry.key,
            confidence: (0.55 + hits.length * .1).clamp(0, 0.95).toDouble(),
            evidence: hits,
            adapter: '${entry.key.name}Adapter');
      }
    }
    final widgets = files.where((f) => f.isWidget).toList();
    if (widgets.isNotEmpty) {
      return StateManagementResult(
          framework: StateManagement.setState,
          confidence: .35,
          evidence: const [
            Evidence('widget usage',
                'Flutter widget classes found; no external state library evidence')
          ],
          adapter: 'setStateAdapter');
    }
    return const StateManagementResult(
        framework: StateManagement.unknown,
        confidence: .0,
        evidence: [Evidence('absence', 'No known state-management evidence')],
        adapter: 'genericAdapter');
  }
}
