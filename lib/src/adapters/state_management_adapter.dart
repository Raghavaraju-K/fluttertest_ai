
abstract class StateManagementAdapter {
  String get name;
  String wrapHarness(String child);
  bool get supportsStateAwareGeneration;
}
