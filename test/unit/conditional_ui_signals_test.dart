import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:fluttertest_ai/src/analysis/dart_source_analyzer.dart';
import 'package:fluttertest_ai/src/project/models.dart';

/// Regression coverage for the "guaranteed on first paint" rule: a UI signal
/// (visible text, a stable key, a button, a text field, a form, a loading
/// indicator) must only feed a `find.*`-asserting generated test when it is
/// unconditionally built. Otherwise the generated `testWidgets` block is a
/// guaranteed failure the moment the gating condition starts out false.
void main() {
  late Directory temp;
  setUp(
      () => temp = Directory.systemTemp.createTempSync('conditional-signals-'));
  tearDown(() => temp.deleteSync(recursive: true));

  DartFileInfo analyzeSource(String source, {String name = 'sample.dart'}) {
    final file = File(p.join(temp.path, name))..writeAsStringSync(source);
    return DartSourceAnalyzer().analyze(file);
  }

  group('visibleTexts', () {
    test('text inside a collection-if is excluded', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.submitted = false});
  final bool submitted;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Text('Welcome back'),
          if (submitted) const Text('Signed in'),
        ],
      );
}
''');
      expect(file.visibleTexts, contains('Welcome back'));
      expect(file.visibleTexts, isNot(contains('Signed in')));
    });

    test('text inside an if-statement is excluded', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class Banner extends StatelessWidget {
  const Banner({super.key, this.showError = false});
  final bool showError;
  @override
  Widget build(BuildContext context) {
    if (showError) {
      return const Text('Error occurred');
    }
    return const Text('All good');
  }
}
''');
      expect(file.visibleTexts, contains('All good'));
      expect(file.visibleTexts, isNot(contains('Error occurred')));
    });

    test('text inside a ternary is excluded on both branches', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, this.isLoading = false});
  final bool isLoading;
  @override
  Widget build(BuildContext context) =>
      isLoading ? const Text('Loading...') : const Text('Ready');
}
''');
      expect(file.visibleTexts, isNot(contains('Loading...')));
      expect(file.visibleTexts, isNot(contains('Ready')));
    });

    test('text reached only through null-coalescing is excluded', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class MaybeGreeting extends StatelessWidget {
  const MaybeGreeting({super.key, this.override});
  final Widget? override;
  @override
  Widget build(BuildContext context) => override ?? const Text('Hello');
}
''');
      expect(file.visibleTexts, isNot(contains('Hello')));
    });

    test('text inside a loop body is excluded', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class ItemList extends StatelessWidget {
  const ItemList({super.key, this.items = const []});
  final List<String> items;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items) Text(item.isEmpty ? '' : 'Item'),
          const Text('Footer'),
        ],
      );
}
''');
      expect(file.visibleTexts, contains('Footer'));
      expect(file.visibleTexts, isNot(contains('Item')));
    });

    test('unconditional text nested in a non-conditional wrapper is included',
        () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class Welcome extends StatelessWidget {
  const Welcome({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: const [
            Text('Welcome back'),
            Text('Continue'),
          ],
        ),
      );
}
''');
      expect(file.visibleTexts, containsAll(['Welcome back', 'Continue']));
    });
  });

  group('keys', () {
    test('a key on a conditionally-rendered widget is excluded', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.submitted = false});
  final bool submitted;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextFormField(key: const ValueKey('email-field')),
          if (submitted) const Text('Signed in', key: ValueKey('signed-in')),
        ],
      );
}
''');
      expect(file.keys, contains('email-field'));
      expect(file.keys, isNot(contains('signed-in')));
    });

    test('a key on an unconditional widget is included', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key});
  @override
  Widget build(BuildContext context) => ElevatedButton(
        key: const ValueKey('submit-button'),
        onPressed: () {},
        child: const Text('Continue'),
      );
}
''');
      expect(file.keys, contains('submit-button'));
    });
  });

  group('buttonTypes, hasTextField, hasForm, loadingIndicators', () {
    test('a button only ever built behind a condition is excluded', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class ConditionalRetry extends StatelessWidget {
  const ConditionalRetry({super.key, this.failed = false});
  final bool failed;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (failed) ElevatedButton(onPressed: () {}, child: const Text('Retry')),
        ],
      );
}
''');
      expect(file.buttonTypes, isNot(contains('ElevatedButton')));
    });

    test(
        'a button with one unconditional occurrence is still included even '
        'when a second occurrence is conditional', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class MixedButtons extends StatelessWidget {
  const MixedButtons({super.key, this.failed = false});
  final bool failed;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          ElevatedButton(onPressed: () {}, child: const Text('Submit')),
          if (failed) ElevatedButton(onPressed: () {}, child: const Text('Retry')),
        ],
      );
}
''');
      expect(file.buttonTypes, contains('ElevatedButton'));
    });

    test(
        'a text field only built behind a condition does not set '
        'hasTextField', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class ConditionalField extends StatelessWidget {
  const ConditionalField({super.key, this.editing = false});
  final bool editing;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (editing) TextField(key: const ValueKey('edit-field')),
        ],
      );
}
''');
      expect(file.hasTextField, isFalse);
      expect(file.textFieldTypes, isEmpty);
    });

    test('a Form only built behind a condition does not set hasForm', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class ConditionalForm extends StatelessWidget {
  const ConditionalForm({super.key, this.show = false});
  final bool show;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (show) Form(child: const SizedBox()),
        ],
      );
}
''');
      expect(file.hasForm, isFalse);
    });

    test('a loading indicator only built behind a condition is excluded', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class ConditionalSpinner extends StatelessWidget {
  const ConditionalSpinner({super.key, this.loading = false});
  final bool loading;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (loading) const CircularProgressIndicator(),
        ],
      );
}
''');
      expect(
          file.loadingIndicators, isNot(contains('CircularProgressIndicator')));
    });

    test('an unconditional loading indicator is still included', () {
      final file = analyzeSource('''
import 'package:flutter/material.dart';

class AlwaysSpinner extends StatelessWidget {
  const AlwaysSpinner({super.key});
  @override
  Widget build(BuildContext context) => const CircularProgressIndicator();
}
''');
      expect(file.loadingIndicators, contains('CircularProgressIndicator'));
    });
  });
}
