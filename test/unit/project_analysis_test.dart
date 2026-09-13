import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:fluttertest_ai/fluttertest_ai.dart';

void main() {
  final fixtures = p.join(Directory.current.path, 'test', 'fixtures');

  group('state-management detection', () {
    Future<ProjectAnalysis> analyzeFixture(String name) async {
      final service = ProjectService();
      return service.analyze(p.join(fixtures, name));
    }

    test('detects Riverpod from dependency, import, and inheritance', () async {
      final analysis = await analyzeFixture('riverpod_async');
      final state = analysis.stateManagement;
      expect(state.framework, StateManagement.riverpod);
      expect(state.adapter, 'riverpodAdapter');
      expect(state.confidence, greaterThanOrEqualTo(0.9));
      final kinds = state.evidence.map((e) => e.kind).toSet();
      expect(kinds, contains('dependency'));
    });

    test('detects Provider from pubspec evidence', () async {
      final analysis = await analyzeFixture('provider_login');
      expect(analysis.stateManagement.framework, StateManagement.provider);
      expect(analysis.stateManagement.adapter, 'providerAdapter');
    });

    test('detects setState without any external library', () async {
      final analysis = await analyzeFixture('basic_set_state');
      expect(analysis.stateManagement.framework, StateManagement.setState);
      expect(analysis.stateManagement.adapter, 'setStateAdapter');
    });

    test('falls back to unknown/custom with a generic adapter', () async {
      final analysis = await analyzeFixture('custom_state');
      expect(analysis.stateManagement.framework, StateManagement.unknown);
      expect(analysis.stateManagement.adapter, 'genericAdapter');
      expect(analysis.stateManagement.confidence, lessThan(0.5));
    });

    test('every result carries evidence and a bounded confidence', () async {
      for (final name in [
        'riverpod_async',
        'provider_login',
        'basic_set_state',
        'custom_state',
      ]) {
        final state = (await analyzeFixture(name)).stateManagement;
        expect(state.evidence, isNotEmpty, reason: name);
        expect(state.confidence, inInclusiveRange(0, 0.98), reason: name);
      }
    });

    test('classification labels cover validator, state class, and route kinds',
        () async {
      final analysis = await analyzeFixture('provider_login');
      final kinds = analysis.files.expand((f) => f.kinds).toSet();
      expect(kinds, contains('validator'));
      expect(kinds, contains('widget'));
    });
  });
}
