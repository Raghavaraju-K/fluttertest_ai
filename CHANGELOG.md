# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1]

### Fixed

- Widget-test generation asserted that every static string found inside a
  `Text(...)` was visible immediately after the first `pump()`, with no
  check for whether that `Text` was conditionally rendered. Any text behind
  a collection-`if`, an `if`/`else`, a ternary, a `??`, a loop, or a
  `switch` produced a `find.text(...)` assertion that failed the instant
  the gating condition started out false (e.g. `if (_submitted)
  Text('Signed in')` when `_submitted` starts `false`) — a pattern common
  to conditionally-rendered error/empty/loading/success states in real
  apps. `DartSourceAnalyzer` now walks the AST ancestor chain of every
  candidate node up to its enclosing function/method body, and only feeds
  `visibleTexts`, `keys`, `buttonTypes`, `textFieldTypes`/`hasTextField`,
  `hasForm`, and `loadingIndicators` when the node is unconditionally
  built. The same conditional-render bug affected keys (`findsOneWidget`
  is even stricter than the text case's `findsWidgets`), buttons, text
  fields, forms, and loading indicators, so all six signals are fixed
  together rather than only the text case.

## [0.2.0]

Corrective release. 0.1.0 generated no unit tests at all, and only a single
"renders without crashing" widget test per screen. Both generation paths are
fixed and verified end to end against real Flutter applications.

### Fixed

- State-management detection now matches structured, tokenised evidence
  (exact dependency names, exact `package:` import package-name segments,
  exact `ClassInfo.superclassName` matches, exact `creationNames` widget
  constructors) instead of substring-matching a lowercased blob of all
  imports/class names concatenated together. The previous approach let the
  GetX token `get` match `package:flutter/widgets.dart` (`get` is a
  substring of "widgets"), misclassifying any Flutter project as GetX.
  Confidence now scales with the number and diversity of independent
  evidence kinds (`dependency`, `import`, `class inheritance`,
  `widget usage`, `behavior`), and precedence between competing frameworks
  is resolved deterministically by comparing confidence rather than by
  hardcoded map iteration order.
- `setState` is no longer inferred merely from "a widget class exists
  somewhere in the project" — it now requires real evidence
  (`DartFileInfo.usesSetState`, and/or a class extending `State`).
  Projects with only `StatelessWidget`s and no `setState()` calls now
  correctly resolve to `unknown`/`genericAdapter`.
- Widget test generator now consumes the already-computed source analysis
  (visible text, keys, button/text-field/form/loading signals) instead of
  re-parsing source and emitting only a render smoke test. Generated tests
  now assert on static UI text, stable keys, button/text-field presence,
  loading indicators, and (when unambiguous) input/tap/form-submit
  interactions, using only stable selectors (keys, text, types).
- Widget test harness selection now delegates to the adapter registry
  (`StateManagementAdapters.forFramework`) instead of a hardcoded Riverpod
  check, so all nine state-management adapters are used for widget-test
  harnesses, not just Riverpod and the generic fallback.
- Widget tests now use the `generatedRegionBegin`/`generatedRegionEnd`
  markers, so `--force` correctly refreshes only the generated region.
- Widgets that read inherited state unsafely for their detected framework
  (`WidgetAnalyzer.requiresUnsafeState`) are now actually skipped with an
  explanatory note, matching the behaviour already documented in report
  limitations text.
- Fixed a source-analysis gap where widget/form/button/loading-indicator
  detection only matched `const`/`new`-prefixed constructor calls; bare
  calls (e.g. `ElevatedButton(onPressed: _increment, ...)`, which cannot be
  `const` when an argument like an instance-method tear-off isn't a
  compile-time constant) were invisible to analysis. This affected nearly
  all real-world widget code, since most non-trivial widget instantiations
  aren't `const`.
- Unit-test generation was fixed so it reliably produces a compiling test
  file for every eligible target (typed top-level functions, static and
  instance methods, getters, `fromJson` factories, and state-container
  lifecycle smoke tests), synthesizing typical, empty, and null-input
  argument lists only where a safe value is known, and deduplicating
  argument lists that would otherwise produce byte-identical test bodies.
- Generated unit-test files now import `package:flutter_test/flutter_test.dart`
  directly, so a generated unit test runs standalone with zero changes to
  the target project's `pubspec.yaml`, instead of depending on an import
  that generation previously omitted.
- Unit-test target selection (`LogicAnalyzer.pureMethodClasses`) was
  broadened from gating eligibility on a class name matching a conventional
  utility-class pattern (`Validator`, `Formatter`, `Mapper`, `Converter`,
  `Parser`, `Helper`, `Calculator`, `Utils`/`Tools`) to a structural check:
  a class is now an eligible unit-test target if it is publicly
  constructible, is not a widget, and exposes at least one public,
  synchronous, non-operator method or getter with synthesizable parameters
  — regardless of its name. Naming convention is now only a confidence
  signal (`hasConventionalName`), not a gate. Classes that are structurally
  eligible but whose name or file imports strongly suggest external I/O
  (`Service`, `Repository`, `Client`, `Api`, `Http`, `Database`, `Db`,
  `Gateway`, `DataSource`; or an import of `dart:io`, `http`, `dio`,
  `shared_preferences`, `sqflite`, or `firebase`) are excluded and reported
  via a recorded skip reason instead of being silently dropped.
- Deterministic repair of a `BlocBuilder` widget test missing its
  `BlocProvider` ancestor was fixed: the repairer now extracts the bloc's
  type from the `BlocBuilder<...>` generic, verifies the type is actually
  constructible from the source file before rewriting anything, wraps the
  harness in `BlocProvider<T>(create: (_) => T(), child: ...)`, and
  normalizes any `package:<project>/lib/...` import produced by generation
  down to the correct `package:<project>/...` form.

## [0.1.0] - 2026-09-13

### Added

- Initial local-first Flutter test analysis, generation, execution, repair, and reporting MVP
- CLI commands: `doctor`, `analyze`, `generate`, `run`, `fix`, `report`
- AST-based source analysis using the Dart `analyzer` package
- State management detection for: setState, Provider, Riverpod, BLoC/Cubit, GetX, Redux, MobX, ValueNotifier, Signals, and custom/unknown
- Dedicated test harness adapters for each supported state management approach
- Generic fallback for unknown state management with behavior-based widget tests
- Unit test generation for: pure functions, validators, formatters, JSON models, utility classes, and state containers
- Widget test generation with proper test harnesses (MaterialApp, ProviderScope, BlocProvider, etc.)
- Conservative test plan with confidence scores and skip reasons
- Safe test writer that never modifies `lib/` or overwrites handwritten tests
- Generated-test ownership marker for safe refresh and repair
- `flutter test` execution with machine-readable (JSON events) and human-readable output parsing
- Deterministic test repair for common failures (missing imports, harness wrappers, finder issues)
- Sanitized report generation (Markdown and JSON) with credential redaction
- Optional AI provider interface with disabled-by-default implementation
- OpenAI-compatible provider stub (opt-in, disabled by default)
- Comprehensive test suite with fixture projects for each supported state management approach
- Support for Windows, macOS, and Linux

[Unreleased]: https://github.com/Raghavaraju-K/fluttertest_ai/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Raghavaraju-K/fluttertest_ai/compare/v0.2.0...v0.2.1
[0.1.0]: https://github.com/Raghavaraju-K/fluttertest_ai/releases/tag/v0.1.0

