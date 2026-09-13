import 'bloc_adapter.dart';
import 'generic_adapter.dart';
import 'getx_adapter.dart';
import 'mobx_adapter.dart';
import 'provider_adapter.dart';
import 'redux_adapter.dart';
import 'riverpod_adapter.dart';
import 'set_state_adapter.dart';
import 'value_notifier_adapter.dart';
import '../project/models.dart';

abstract class StateManagementAdapter {
  const StateManagementAdapter();

  String get name;

  /// Wraps a widget child with the appropriate state-management harness.
  String wrapHarness(String child);

  /// Whether this adapter can generate state-aware tests.
  bool get supportsStateAwareGeneration;

  /// Additional import statements required by this adapter's harness.
  List<String> get extraImports => const [];
}

/// Registry for looking up adapters by state management framework.
class StateManagementAdapters {
  const StateManagementAdapters._();

  static StateManagementAdapter forFramework(StateManagement framework) {
    return switch (framework) {
      StateManagement.riverpod => const RiverpodAdapter(),
      StateManagement.provider => const ProviderAdapter(),
      StateManagement.bloc => const BlocAdapter(),
      StateManagement.getx => const GetxAdapter(),
      StateManagement.redux => const ReduxAdapter(),
      StateManagement.mobx => const MobxAdapter(),
      StateManagement.valueNotifier => const ValueNotifierAdapter(),
      StateManagement.signals => const GenericAdapter(),
      StateManagement.setState => const SetStateAdapter(),
      StateManagement.unknown => const GenericAdapter(),
    };
  }
}
