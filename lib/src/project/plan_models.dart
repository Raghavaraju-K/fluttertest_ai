/// The kind of test a plan item produces.
enum TestKind { unit, widget, integration }

/// What a generator produced for one plan item.
///
/// `content == null` means nothing was safely generatable; [notes] explain why
/// so the writer and reports can surface actionable skip reasons.
class GenerationOutcome {
  const GenerationOutcome(this.content, {this.notes = const []});
  final String? content;
  final List<String> notes;
}

class TestPlanItem {
  const TestPlanItem({
    required this.source,
    required this.output,
    required this.kind,
    required this.confidence,
    required this.reason,
  });
  final String source;
  final String output;
  final TestKind kind;
  final double confidence;
  final String reason;
  Map<String, Object> toJson() => {
        'source': source,
        'output': output,
        'kind': kind.name,
        'confidence': confidence,
        'reason': reason,
      };
}

class TestPlan {
  const TestPlan(this.items, this.skipped);
  final List<TestPlanItem> items;
  final List<String> skipped;
  Map<String, Object> toJson() => {
        'items': [for (final item in items) item.toJson()],
        'skipped': skipped,
      };
}

/// Aggregated result of one `flutter test` invocation over generated tests.
class TestRunResult {
  const TestRunResult({
    required this.exitCode,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.compilationErrors,
    required this.output,
    required this.reportPath,
    this.failuresByFile = const {},
  });
  final int exitCode;
  final int passed;
  final int failed;
  final int skipped;
  final int compilationErrors;

  /// Sanitized (redacted) combined stdout/stderr of the run.
  final String output;
  final String reportPath;

  /// Failure messages grouped by test file path (when available).
  final Map<String, List<String>> failuresByFile;

  bool get succeeded => exitCode == 0;

  Map<String, Object> toJson() => {
        'exitCode': exitCode,
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        'compilationErrors': compilationErrors,
        'reportPath': reportPath,
        'failuresByFile': failuresByFile,
      };
}
