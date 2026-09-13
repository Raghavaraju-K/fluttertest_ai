import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:fluttertest_ai/src/analysis/dart_source_analyzer.dart';
import 'package:fluttertest_ai/src/analysis/logic_analyzer.dart';
import 'package:fluttertest_ai/src/analysis/testability_analyzer.dart';
import 'package:fluttertest_ai/src/project/models.dart';

void main() {
  final logic = LogicAnalyzer();
  final testability = TestabilityAnalyzer();

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('logic-analyzer-'));
  tearDown(() => temp.deleteSync(recursive: true));

  DartFileInfo analyzeSource(String source, {String name = 'sample.dart'}) {
    final file = File(p.join(temp.path, name))..writeAsStringSync(source);
    return DartSourceAnalyzer().analyze(file);
  }

  test('a structurally-eligible class with a non-matching name is selected',
      () {
    final file = analyzeSource('''
class CartTotals {
  int itemCount = 0;
  double subtotal = 0.0;
  void addItem(double price) {
    itemCount++;
    subtotal += price;
  }
  void clear() {
    itemCount = 0;
    subtotal = 0.0;
  }
  bool get isEmpty => itemCount == 0;
  double get withTax => subtotal * 1.2;
}
''');
    final names = logic.pureMethodClasses(file).map((c) => c.name);
    expect(names, contains('CartTotals'));
    expect(logic.hasConventionalName(file.classDetails.single), isFalse);
    // Non-conventional names are still generated, just at a lower confidence
    // than a conventionally-named validator/formatter/... class.
    expect(testability.confidence(file), 0.55);
  });

  test('a conventionally-named class gets a higher confidence boost', () {
    final file = analyzeSource('''
class EmailValidator {
  bool isValid(String? email) => email != null && email.contains('@');
}
''');
    final names = logic.pureMethodClasses(file).map((c) => c.name);
    expect(names, contains('EmailValidator'));
    expect(logic.hasConventionalName(file.classDetails.single), isTrue);
    expect(testability.confidence(file), 0.65);
  });

  test('a widget class is not selected', () {
    final file = analyzeSource('''
import 'package:flutter/material.dart';

class SummaryWidget extends StatelessWidget {
  const SummaryWidget({super.key});
  void refresh() {}
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''');
    expect(logic.pureMethodClasses(file), isEmpty);
    expect(logic.isTestable(file), isFalse);
  });

  test('an abstract class is not selected', () {
    final file = analyzeSource('''
abstract class AbstractHelper {
  void doWork();
}
''');
    expect(logic.pureMethodClasses(file), isEmpty);
    expect(logic.isTestable(file), isFalse);
  });

  test('a class with required constructor args is not selected', () {
    final file = analyzeSource('''
class NeedsDependency {
  NeedsDependency(this.value);
  final int value;
  void run() {}
}
''');
    expect(logic.pureMethodClasses(file), isEmpty);
    expect(logic.isTestable(file), isFalse);
  });

  test('an I/O-suggesting class is skipped with a recorded reason', () {
    final file = analyzeSource('''
class UserRepository {
  List<String> cachedNames() => const ['a'];
}
''');
    expect(logic.pureMethodClasses(file), isEmpty);
    final skips = logic.ioSkippedClasses(file);
    expect(skips, hasLength(1));
    expect(skips.single.name, 'UserRepository');
    expect(skips.single.reason, contains('I/O'));
    // Structurally it would otherwise have qualified, so isTestable must not
    // be tricked into treating it as testable via some other path either.
    expect(logic.isTestable(file), isFalse);
  });

  test('a file importing an I/O package skips its otherwise-eligible classes',
      () {
    final file = analyzeSource('''
import 'package:http/http.dart' as http;

class PricingEngine {
  double total(double amount) => amount;
}
''');
    expect(logic.pureMethodClasses(file), isEmpty);
    final skips = logic.ioSkippedClasses(file);
    expect(skips, hasLength(1));
    expect(skips.single.name, 'PricingEngine');
    expect(skips.single.reason, contains('imports an I/O package'));
  });
}
