import 'generic_adapter.dart';

class BlocAdapter extends GenericAdapter {
  const BlocAdapter();
  @override
  String get name => 'blocAdapter';
  @override
  bool get supportsStateAwareGeneration => true;
}
