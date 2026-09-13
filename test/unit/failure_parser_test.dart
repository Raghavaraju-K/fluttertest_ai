import 'package:test/test.dart';

import 'package:fluttertest_ai/fluttertest_ai.dart';
import 'package:fluttertest_ai/src/execution/test_failure_parser.dart';

void main() {
  test('recognizes Flutter failures and compilation errors', () {
    final result = TestFailureParser().parse(
        1,
        '+2\n══╡ EXCEPTION CAUGHT\nCompilation failed\nError: missing import',
        'run.json');
    expect(result.passed, 2);
    expect(result.failed, greaterThan(0));
    expect(result.compilationErrors, greaterThan(0));
  });

  group('machine (JSON events) parsing', () {
    const machineOutput = '''
{"type":"suite","suite":{"id":1,"path":"test/widgets/login_widget_test.dart"}}
{"type":"testStart","test":{"id":3,"suiteID":1,"name":"LoginScreen renders"}}
{"type":"testStart","test":{"id":4,"suiteID":1,"name":"LoginScreen shows title"}}
{"type":"error","testID":4,"error":"Expected: exactly one matching node\\n  found: 0","isFailure":true}
{"type":"testDone","testID":3,"result":"success","hidden":false}
{"type":"testDone","testID":4,"result":"failure","hidden":false}
{"type":"testStart","test":{"id":5,"suiteID":1,"name":"skipped smoke"}}
{"type":"testDone","testID":5,"result":"skipped","hidden":false}
{"type":"done","success":false}
''';

    test('counts passed, failed, and skipped tests', () {
      final parsed =
          TestFailureParser().parseMachine(1, machineOutput, 'run.json');
      final result = parsed.result;
      expect(result.passed, 1);
      expect(result.failed, 1);
      expect(result.skipped, 1);
      expect(result.compilationErrors, 0);
    });

    test('groups failure messages by suite file path', () {
      final parsed =
          TestFailureParser().parseMachine(1, machineOutput, 'run.json');
      expect(parsed.failuresByFile.keys,
          contains('test/widgets/login_widget_test.dart'));
      final messages =
          parsed.failuresByFile['test/widgets/login_widget_test.dart']!;
      expect(messages.join(' '), contains('found: 0'));
    });

    test('treats load errors as compilation errors', () {
      const output =
          '{"type":"error","error":"test/generated_test.dart: Error: URI does not exist"}';
      final parsed = TestFailureParser().parseMachine(1, output, 'run.json');
      expect(parsed.result.compilationErrors, 1);
      expect(parsed.result.failed, 0);
    });
  });

  group('redaction', () {
    test('redacts secret-like key-value pairs from saved run output', () {
      final redacted = TestFailureParser.redact(
          'error: api_key=sk-1234567890abcdef token: t-secret\n'
          'FLUTTERTEST_VAR=whatever password: p1\n'
          'normal text stays');
      expect(redacted, isNot(contains('sk-1234567890abcdef')));
      expect(redacted, isNot(contains('t-secret')));
      expect(redacted, isNot(contains('whatever')));
      expect(redacted, isNot(contains('p1')));
      expect(redacted, contains('normal text stays'));
    });
  });
}
