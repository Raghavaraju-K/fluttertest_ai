import 'generic_adapter.dart';

class RiverpodAdapter extends GenericAdapter {
  const RiverpodAdapter();
  @override
  String get name => 'riverpodAdapter';
  @override
  String wrapHarness(String child) => 'ProviderScope(child: $child)';
  @override
  List<String> get extraImports =>
      const ["import 'package:flutter_riverpod/flutter_riverpod.dart';"];
  @override
  bool get supportsStateAwareGeneration => true;
}
