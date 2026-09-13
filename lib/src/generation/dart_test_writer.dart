import 'dart:io';
import 'package:path/path.dart' as p;

import '../project/models.dart';
import '../project/plan_models.dart';
import '../templates/templates.dart';
import 'integration_test_generator.dart';
import 'unit_test_generator.dart';
import 'widget_test_generator.dart';

class WriteResult {
  const WriteResult(this.written, this.skipped);
  final List<String> written;
  final List<String> skipped;
}

/// Writes generated tests only under `test/` (and `integration_test/` for the
/// integration kind). Handwritten files are never overwritten; previously
/// generated files are refreshed only inside their marked generated region.
class DartTestWriter {
  DartTestWriter({
    UnitTestGenerator? unit,
    WidgetTestGenerator? widget,
    IntegrationTestGenerator? integration,
  })  : _unit = unit ?? UnitTestGenerator(),
        _widget = widget ?? WidgetTestGenerator(),
        _integration = integration ?? IntegrationTestGenerator();
  final UnitTestGenerator _unit;
  final WidgetTestGenerator _widget;
  final IntegrationTestGenerator _integration;

  Future<WriteResult> write(
    TestPlan plan,
    ProjectAnalysis analysis, {
    bool dryRun = false,
    bool force = false,
  }) async {
    final written = <String>[];
    final skipped = <String>[];
    for (final item in plan.items) {
      final outcome = switch (item.kind) {
        TestKind.unit => _unit.generate(item, analysis),
        TestKind.widget => _widget.generate(item, analysis),
        TestKind.integration => _integration.generate(item, analysis),
      };
      final relativeOutput = _relative(item, analysis);
      if (outcome.content == null) {
        skipped.add('$relativeOutput: ${outcome.notes.join('; ')}');
        continue;
      }
      final target = File(item.output);
      var content = outcome.content!;
      if (await target.exists()) {
        final existing = await target.readAsString();
        if (!existing.contains(generatedMarker)) {
          skipped.add('$relativeOutput: handwritten test preserved');
          continue;
        }
        if (!force) {
          skipped.add(
              '$relativeOutput: generated test already exists (use --force to refresh)');
          continue;
        }
        content = _refreshRegion(existing, content);
      }
      written.add(relativeOutput);
      if (!dryRun) {
        await target.parent.create(recursive: true);
        await target.writeAsString(content);
      }
    }
    return WriteResult(written, skipped);
  }

  String _relative(TestPlanItem item, ProjectAnalysis analysis) =>
      p.relative(item.output, from: analysis.root);

  /// Replaces only the generated region, preserving user-owned content that
  /// appears before the begin marker.
  String _refreshRegion(String existing, String generated) {
    final beginIndex = existing.indexOf('// $generatedRegionBegin');
    if (beginIndex < 0) return generated;
    return existing.substring(0, beginIndex) + generated;
  }
}
