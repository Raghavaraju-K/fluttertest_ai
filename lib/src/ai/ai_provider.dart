abstract class AiProvider {
  bool get enabled;
  Future<List<String>> suggestEdgeCases(String summary);
}
