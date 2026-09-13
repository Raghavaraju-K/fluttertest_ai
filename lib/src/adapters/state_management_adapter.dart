import '../project/models.dart';
import 'bloc_adapter.dart';
import 'generic_adapter.dart';
import 'getx_adapter.dart';
import 'mobx_adapter.dart';
import 'provider_adapter.dart';
import 'redux_adapter.dart';
import 'riverpod_adapter.dart';
import 'set_state_adapter.dart';
import 'value_notifier_adapter.dart';

/// Base contract every state-management adapter implements.
///
/// Adapters translate detection results into a safe widget-test harness and
/// optional extra imports. Adapters that cannot construct their state
/// generically (Provider, BLoC, GetX, ...) keep the identity harness and rely
/// on the generator's consumption checks to skip unsafe widgets.
abstract class StateManagementAdapter {
  const StateManagementAdapter();

  String get name;

  /// Wraps the app shell used inside `pumpWidget`.
  String wrapHarness(String child) => child;

  /// Extra import lines the harness requires in generated test files.
  List<String> get extraImports => const [];

  /// Whether the adapter can help generate state-aware unit tests.
  bool get supportsStateAwareGeneration => false;
}

/// Registry mapping a detected framework to its adapter.
class StateManagementAdapters {
  const StateManagementAdapters._();

  static StateManagementAdapter forFramework(StateManagement framework) =>
      switch (framework) {
        StateManagement.riverpod => const RiverpodAdapter(),
        StateManagement.bloc => const BlocAdapter(),
        StateManagement.provider => const ProviderAdapter(),
        StateManagement.getx => const GetxAdapter(),
        StateManagement.redux => const ReduxAdapter(),
        StateManagement.mobx => const MobxAdapter(),
        StateManagement.valueNotifier => const ValueNotifierAdapter(),
        StateManagement.setState => const SetStateAdapter(),
        // Signals and unknown/custom architectures fall back to the generic,
        // behavior-based adapter.
        StateManagement.signals => const GenericAdapter(),
        StateManagement.unknown => const GenericAdapter(),
      };
}
