import 'package:mason_logger/mason_logger.dart';

import '../version.dart';
import '../project/models.dart';
import '../project/plan_models.dart';

/// Colored, cross-platform console output (mason_logger based).
class ConsoleReporter {
  ConsoleReporter({Logger? logger}) : logger = logger ?? Logger();
  final Logger logger;

  void banner() {
    logger.info('FlutterTest AI v$packageVersion');
  }

  void section(String text) {
    logger.info('\n$text');
  }

  /// [ok] tri-state: true → ✓, false → ✗, null → neutral – prefix.
  void line(String text, {bool? ok = true}) {
    final prefix = switch (ok) {
      true => '✓ ',
      false => '✗ ',
      null => '- ',
    };
    if (ok == false) {
      logger.err('$prefix$text');
    } else {
      logger.info('$prefix$text');
    }
  }

  void analysis(ProjectAnalysis analysis) {
    banner();
    logger.info('\nAnalyzing Flutter project...');
    line('Flutter project detected: ${analysis.projectName}');
    line('State management: ${analysis.stateManagement.framework.label} '
        '(${(analysis.stateManagement.confidence * 100).round()}% confidence, '
        'adapter: ${analysis.stateManagement.adapter})');
    for (final evidence in analysis.stateManagement.evidence) {
      logger.info('    ${evidence.kind}: ${evidence.value}');
    }
    line('Screens detected: ${analysis.widgetCount}');
    line('Testable classes detected: ${analysis.testableClassCount}');
    line('Existing tests found: ${analysis.existingTests.length}');
    if (analysis.skipped.isNotEmpty) {
      section('Skipped files:');
      for (final reason in analysis.skipped) {
        logger.info('    - $reason');
      }
    }
  }

  void run(TestRunResult result) {
    if (result.succeeded) {
      line('${result.passed} passed, ${result.skipped} skipped');
    } else {
      line(
          '${result.passed} passed, ${result.failed} failed, '
          '${result.compilationErrors} compilation error(s)',
          ok: false);
    }
  }
}
