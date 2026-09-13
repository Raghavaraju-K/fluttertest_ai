import 'dart:io';
import 'ai_provider.dart';

/// Deliberately does not send source by default. A transport can be supplied by an opt-in integration.
class OpenAiCompatibleProvider implements AiProvider {
  OpenAiCompatibleProvider()
      : _enabled =
            Platform.environment['FLUTTERTEST_AI_ENABLE_EXTERNAL_AI'] == 'true';
  final bool _enabled;
  @override
  bool get enabled => _enabled;
  @override
  Future<List<String>> suggestEdgeCases(String summary) async => const [];
}
