import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:fluttertest_ai/fluttertest_ai.dart';

void main() {
  /// Creates a generated-only workspace with the given test file content.
  Future<(Directory, File, File)> workspace() async {
    final root = await Directory.systemTemp.createTemp('fluttertest-ai-fix-');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml'))
        .writeAsStringSync('name: sample\ndependencies:\n  flutter: any\n');
    final lib = File(p.join(root.path, 'lib', 'login.dart'))
      ..parent.createSync(recursive: true);
    lib.writeAsStringSync('class LoginScreen {}\n');
    final generated = File(p.join(root.path, 'test', 'login_widget_test.dart'))
      ..parent.createSync(recursive: true);
    final handwritten = File(p.join(root.path, 'test', 'manual_test.dart'));
    return (root, generated, handwritten);
  }

  const marker = '// fluttertest_ai: generated region begin; confidence=0.75';
  const footer = '// fluttertest_ai: generated region end';

  test('wraps pumpWidget with ProviderScope inside generated files only',
      () async {
    final (root, generated, handwritten) = await workspace();
    generated.writeAsStringSync('''
$marker
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LoginScreen renders', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
$footer
''');
    final result = await GeneratedTestRepairer()
        .repair(root.path, 'ProviderScope was missing');
    expect(result.changed, hasLength(1));
    final content = generated.readAsStringSync();
    expect(
        content,
        contains(
            'pumpWidget(ProviderScope(child: MaterialApp(home: LoginScreen())));'));
    expect(content, contains(marker));
  });

  test('never touches handwritten test files', () async {
    final (root, _, handwritten) = await workspace();
    handwritten.writeAsStringSync('void main() {}');
    final result = await GeneratedTestRepairer()
        .repair(root.path, 'ProviderScope was missing');
    expect(result.changed, isEmpty);
    expect(handwritten.readAsStringSync(), 'void main() {}');
  });

  test('switches pump to pumpAndSettle on finder failures', () async {
    final (root, generated, _) = await workspace();
    generated.writeAsStringSync('''
$marker
void body() {
  await tester.pump();
  expect(find.text('Login'), findsOneWidget);
}
$footer
''');
    final result = await GeneratedTestRepairer().repair(
      root.path,
      'Expected: exactly one matching node\n  found: 0',
    );
    expect(result.changed, hasLength(1));
    expect(generated.readAsStringSync(), contains('pumpAndSettle();'));
  });

  test('adds BlocProvider only when the bloc class is safely constructible',
      () async {
    final (root, generated, _) = await workspace();
    File(p.join(root.path, 'lib', 'login.dart')).writeAsStringSync('''
class LoginBloc {
  const LoginBloc();
}
''');
    generated.writeAsStringSync('''
$marker
import 'package:sample/lib/login.dart';
import 'package:flutter/material.dart';

void body() {
  await tester.pumpWidget(MaterialApp(home: LoginScreen()));
  await tester.pump();
  expect(find.byType(BlocBuilder<LoginBloc, int>), findsOneWidget);
}
$footer
''');
    final result = await GeneratedTestRepairer().repair(
      root.path,
      'BlocProvider.of() called with a context that does not contain a Bloc',
    );
    expect(result.changed, hasLength(1));
    final content = generated.readAsStringSync();
    expect(
        content,
        contains(
            'BlocProvider<LoginBloc>(create: (_) => LoginBloc(), child: MaterialApp(home: LoginScreen()))'));
    expect(content, isNot(contains('package:sample/lib/')));
  });
}
