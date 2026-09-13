import 'package:path/path.dart' as p;

import '../analysis/logic_analyzer.dart';
import '../analysis/testability_analyzer.dart';
import '../project/models.dart';
import '../project/plan_models.dart';

/// Builds a conservative test plan: which files get which kind of test,
/// written where, at which confidence — and why anything is skipped.
class TestPlanBuilder {
  TestPlanBuilder({TestabilityAnalyzer? testability, LogicAnalyzer? logic})
      : _testability = testability ?? TestabilityAnalyzer(),
        _logic = logic ?? LogicAnalyzer();
  final TestabilityAnalyzer _testability;
  final LogicAnalyzer _logic;

  TestPlan build(ProjectAnalysis analysis, {TestKind? only}) {
    final items = <TestPlanItem>[];
    final skipped = <String>[...analysis.skipped];
    for (final file in analysis.files) {
      final relative = p.relative(file.path, from: analysis.root);
      final libRelative = _libRelative(relative);
      if (libRelative == null) {
        skipped.add('$relative: file is not under lib/');
        continue;
      }
      final base = p.withoutExtension(libRelative.replaceAll(p.separator, '/'));
      final emitted = <TestKind>{};
      if ((only == null || only == TestKind.unit) && _logic.isTestable(file)) {
        items.add(TestPlanItem(
          source: file.path,
          output: _under(analysis.root, ['test', '${base}_test.dart']),
          kind: TestKind.unit,
          confidence: _testability.confidence(file),
          reason: 'unit targets — ${_unitTargets(file)}',
        ));
        emitted.add(TestKind.unit);
      }
      if ((only == null || only == TestKind.widget) &&
          file.constructibleWidgets.isNotEmpty) {
        items.add(TestPlanItem(
          source: file.path,
          output: _under(analysis.root, ['test', '${base}_widget_test.dart']),
          kind: TestKind.widget,
          confidence: _testability.confidence(file),
          reason:
              'widget harness for ${file.constructibleWidgets.map((w) => w.name).join(', ')}',
        ));
        emitted.add(TestKind.widget);
      }
      if (only == TestKind.integration &&
          p.basename(file.path) == 'main.dart' &&
          file.constructibleWidgets.isNotEmpty) {
        items.add(TestPlanItem(
          source: file.path,
          output: _under(
              analysis.root, ['integration_test', '${base}_smoke_test.dart']),
          kind: TestKind.integration,
          confidence: _testability.confidence(file) * 0.8,
          reason:
              'integration smoke test for ${file.constructibleWidgets.first.name}',
        ));
        emitted.add(TestKind.integration);
      }
      if (emitted.isEmpty) {
        skipped.add(
            '$relative: no conservative ${only?.name ?? 'test'} candidate (kinds: ${file.kinds.join(', ')})');
      }
    }
    if (only == TestKind.integration && items.isEmpty) {
      skipped
          .add('integration: no launchable lib/main.dart widget candidate; the '
              'integration_test dependency is verified at generation time');
    }
    return TestPlan(items, skipped);
  }

  String _under(String root, List<String> segments) =>
      p.normalize(p.joinAll([root, ...segments]));

  String? _libRelative(String relativeFromRoot) {
    final parts = p.split(relativeFromRoot);
    if (parts.isEmpty || parts.first != 'lib') return null;
    return p.joinAll(parts.sublist(1));
  }

  String _unitTargets(DartFileInfo file) {
    final targets = <String>[
      '${_logic.unitFunctions(file).length} function(s)',
      '${_logic.lifecycleClasses(file).length} state container(s)',
      '${_logic.serializableClasses(file).length} serializable type(s)',
      '${_logic.pureMethodClasses(file).length} utility class(es)',
    ];
    return targets.join(', ');
  }
}
