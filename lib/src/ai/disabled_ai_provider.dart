import 'ai_provider.dart';

class DisabledAiProvider implements AiProvider {
  const DisabledAiProvider();
  @override
  bool get enabled => false;
  @override
  Future<List<String>> suggestEdgeCases(String summary) async => const [];
}
