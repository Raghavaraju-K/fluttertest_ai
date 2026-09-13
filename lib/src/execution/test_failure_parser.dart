import 'dart:convert';

import '../project/plan_models.dart';

/// Aggregated machine-report data used by the repairer.
class ParsedRun {
  const ParsedRun({required this.result, required this.failuresByFile});
  final TestRunResult result;
  final Map<String, List<String>> failuresByFile;
}

/// Parses `flutter test` output in machine (JSON events) and human formats
/// and redacts secret-like values before anything is persisted or reported.
class TestFailureParser {
  /// Redacts API keys, tokens, passwords, and environment-variable style
  /// assignments so reports never store credential-like values.
  static String redact(String text) {
    var result = text.replaceAllMapped(
      RegExp(
          r'\b(api[_-]?key|apikey|token|secret|password|passwd|authorization)\b'
          r'\s*[:=]\s*\S+',
          caseSensitive: false),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'\b([A-Z][A-Z0-9_]{2,})=\S+'),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    return result;
  }

  /// Parses `flutter test --machine` JSON-lines output into counts plus
  /// per-file failure messages.
  ParsedRun parseMachine(int exitCode, String output, String reportPath) {
    var passed = 0;
    var failed = 0;
    var skipped = 0;
    var compilationErrors = 0;
    final suitePaths = <int, String>{};
    final testSuite = <int, int>{};
    final testErrors = <int, String>{};
    final failuresByFile = <String, List<String>>{};

    void attachFailure(int? testId, String message) {
      final suiteId = testSuite[testId];
      final path = suiteId == null ? null : suitePaths[suiteId];
      if (path != null) {
        failuresByFile.putIfAbsent(path, () => []).add(message);
      }
    }

    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('{')) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final type = decoded['type'];
      if (type == 'suite') {
        final suite = decoded['suite'];
        if (suite is Map && suite['id'] is int && suite['path'] is String) {
          suitePaths[suite['id'] as int] = suite['path'] as String;
        }
      } else if (type == 'testStart') {
        final test = decoded['test'];
        if (test is Map && test['id'] is int && test['suiteID'] is int) {
          testSuite[test['id'] as int] = test['suiteID'] as int;
        }
      } else if (type == 'error') {
        final message = '${decoded['error']}';
        final testId =
            decoded['testID'] is int ? decoded['testID'] as int : null;
        if (testId != null) testErrors[testId] = message;
        // Errors that are not test failures are load/compilation errors.
        if (decoded['isFailure'] != true) compilationErrors++;
      } else if (type == 'testDone') {
        final testId = decoded['testID'];
        final outcome = decoded['result'];
        final hidden = decoded['hidden'] == true;
        if (outcome is! String || testId is! int) continue;
        switch (outcome) {
          case 'success':
            if (!hidden) passed++;
          case 'skipped':
            if (!hidden) skipped++;
          case 'failure' || 'error' || 'crash':
            if (!hidden) failed++;
            final message = testErrors[testId];
            if (message != null) attachFailure(testId, message);
        }
      }
    }
    if (compilationErrors == 0 &&
        passed == 0 &&
        failed == 0 &&
        skipped == 0 &&
        exitCode != 0) {
      // The whole run failed before any test executed: treat it as a
      // compilation error so the repair layer gets a chance to act.
      compilationErrors++;
    }
    final result = TestRunResult(
      exitCode: exitCode,
      passed: passed,
      failed: failed,
      skipped: skipped,
      compilationErrors: compilationErrors,
      output: redact(output),
      reportPath: reportPath,
      failuresByFile: failuresByFile,
    );
    return ParsedRun(result: result, failuresByFile: failuresByFile);
  }

  /// Human-readable fallback used when machine output is unavailable.
  TestRunResult parse(int exitCode, String output, String reportPath) {
    final passed = RegExp(r'\+(\d+)')
        .allMatches(output)
        .map((match) => int.parse(match.group(1)!))
        .fold(0, (best, value) => value > best ? value : best);
    final failureMarkers = RegExp(
            r'(?:Some tests failed|Failed assertion|══╡ EXCEPTION CAUGHT)',
            multiLine: true)
        .allMatches(output)
        .length;
    final skipped =
        RegExp(r'\bskipped\b', caseSensitive: false).allMatches(output).length;
    final compilation =
        RegExp(r'(?:Compilation failed|Error:)', multiLine: true)
            .allMatches(output)
            .length;
    final failed = exitCode == 0 ? 0 : failureMarkers.clamp(1, 9999).toInt();
    return TestRunResult(
      exitCode: exitCode,
      passed: passed,
      failed: failed,
      skipped: skipped,
      compilationErrors: compilation,
      output: redact(output),
      reportPath: reportPath,
    );
  }
}
