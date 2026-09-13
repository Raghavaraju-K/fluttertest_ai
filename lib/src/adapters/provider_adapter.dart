import 'generic_adapter.dart';

class ProviderAdapter extends GenericAdapter {
  const ProviderAdapter();
  @override
  String get name => 'providerAdapter';
  @override
  bool get supportsStateAwareGeneration => true;
}
