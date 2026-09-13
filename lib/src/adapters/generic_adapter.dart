import 'state_management_adapter.dart';

/// Fallback adapter for unknown or custom state management. Generates
/// conservative behavior-based widget tests without any state harness.
class GenericAdapter extends StateManagementAdapter {
  const GenericAdapter();

  @override
  String get name => 'genericAdapter';

  @override
  String wrapHarness(String child) => child;

  @override
  bool get supportsStateAwareGeneration => false;

  @override
  List<String> get extraImports => const [];
}
