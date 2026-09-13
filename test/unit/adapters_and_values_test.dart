import 'package:test/test.dart';

import 'package:fluttertest_ai/fluttertest_ai.dart';
import 'package:fluttertest_ai/src/adapters/generic_adapter.dart';
import 'package:fluttertest_ai/src/adapters/riverpod_adapter.dart';
import 'package:fluttertest_ai/src/generation/integration_test_generator.dart';
import 'package:fluttertest_ai/src/generation/value_fixtures.dart';

void main() {
  group('adapters', () {
    test('registry selects the adapter for each detected framework', () {
      expect(StateManagementAdapters.forFramework(StateManagement.riverpod),
          isA<RiverpodAdapter>());
      expect(StateManagementAdapters.forFramework(StateManagement.unknown),
          isA<GenericAdapter>());
    });

    test('Riverpod wraps the harness and adds its import', () {
      const adapter = RiverpodAdapter();
      expect(adapter.wrapHarness('MaterialApp(home: X())'),
          'ProviderScope(child: MaterialApp(home: X()))');
      expect(adapter.extraImports,
          contains("import 'package:flutter_riverpod/flutter_riverpod.dart';"));
      expect(adapter.supportsStateAwareGeneration, isTrue);
    });

    test('generic adapter keeps the identity harness', () {
      const adapter = GenericAdapter();
      expect(adapter.wrapHarness('MaterialApp(home: X())'),
          'MaterialApp(home: X())');
      expect(adapter.extraImports, isEmpty);
    });
  });

  group('value fixtures', () {
    const values = ValueFixtures();

    test('synthesizes typical and empty literals for supported types', () {
      expect(values.typical(_prm('String')), "'sample'");
      expect(values.empty(_prm('String')), "''");
      expect(values.typical(_prm('int')), '1');
      expect(values.empty(_prm('int')), '0');
      expect(values.empty(_prm('String?')), 'null');
      expect(values.typical(_prm('List<String>')), "const <String>['a']");
      expect(values.empty(_prm('Map<String, int>')), 'const <String, int>{}');
      expect(values.typical(_prm('Set<bool>')), 'const <bool>{true}');
    });

    test('refuses unsupported or unsafe parameter types', () {
      expect(values.typical(_prm('Function')), isNull);
      expect(values.typical(_prm('EmailValidator')), isNull);
      expect(values.empty(_prm('Function')), isNull);
      expect(values.typical(_prm('List<List<int>>')), isNull);
    });
  });

  group('integration generator', () {
    test('explains a skip when the integration_test dependency is missing', () {
      const item = TestPlanItem(
          source: 'lib/main.dart',
          output: 'integration_test/main_smoke_test.dart',
          kind: TestKind.integration,
          confidence: 0.7,
          reason: 'smoke');
      const analysis = ProjectAnalysis(
          root: '.',
          projectName: 'sample',
          files: [],
          stateManagement: StateManagementResult(
              framework: StateManagement.unknown,
              confidence: 0,
              evidence: [],
              adapter: 'genericAdapter'),
          existingTests: [],
          skipped: []);
      final outcome = const IntegrationTestGenerator().generate(item, analysis);
      expect(outcome.content, isNull);
      expect(outcome.notes.join(' '), contains('never modifies pubspec.yaml'));
    });
  });
}

/// Builds a [ParameterInfo] with just a type source.
ParameterInfo _prm(String type) => ParameterInfo(
      name: 'value',
      typeSource: type,
      isRequiredPositional: true,
      isRequiredNamed: false,
      isNullable: type.endsWith('?'),
    );
