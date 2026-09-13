# Contributing

Thanks for contributing to FlutterTest AI. This document covers local setup,
verification, how the test fixtures work, how to add a new state-management
adapter, and the project's hard rules.

## Local Setup

```bash
git clone https://github.com/Raghavaraju-K/fluttertest_ai.git
cd fluttertest_ai
dart pub get
```

The package requires Dart SDK `>=3.4.0 <4.0.0`. A Flutter SDK on `PATH` is
required to run the fixture projects and any generated tests, since fixtures
depend on `flutter_test` and framework packages such as `flutter_riverpod`
and `flutter_bloc`.

## Verification

Run all three before opening a pull request:

```bash
dart format .
dart analyze
dart test
```

- `dart format .` must produce no diff.
- `dart analyze` must be clean (no errors or warnings).
- `dart test` must pass in full. The suite currently has 41 tests. Never
  submit a change with a failing or skipped test — fix it or explain why in
  the pull request description.

## Test Fixtures (`test/fixtures/*`)

Each fixture under `test/fixtures/` is a minimal, self-contained Flutter
project used to exercise detection, generation, execution, and repair
end-to-end against real source code rather than mocked analyzer output.
Current fixtures:

- `basic_set_state/` — a default `flutter create`-style app with `setState`
- `provider_login/` — a small screen using `provider`/`ChangeNotifier`
- `riverpod_async/` — a screen using `flutter_riverpod`
- `bloc_search/` — a screen using `flutter_bloc`
- `custom_state/` — state management with no recognizable evidence, to
  exercise the generic fallback

Each fixture has its own `pubspec.yaml` and a `lib/` directory with realistic
widget and logic code — not a synthetic snippet. Unit and integration tests
under `test/unit/` and `test/integration/` point the analyzer, detector, and
generators at these fixtures and assert on the resulting `ProjectAnalysis`,
`TestPlan`, or generated file content.

### Adding a new fixture

1. Create `test/fixtures/<name>/` with a `pubspec.yaml` declaring only the
   dependencies relevant to the scenario you're testing, and a `lib/`
   directory with real, compilable Dart code that exhibits the
   state-management pattern or edge case you want covered.
2. Keep it minimal — a fixture should isolate one scenario (one framework,
   one edge case), not model a full app.
3. Reference the new fixture path from a test in `test/unit/` or
   `test/integration/` and assert on the specific behaviour you added the
   fixture for.
4. Run `dart test` to confirm the new fixture is picked up and passes.

## Adding a New State-Management Adapter

Adapters live in `lib/src/adapters/`. Each adapter implements
`StateManagementAdapter` (defined in
`lib/src/adapters/state_management_adapter.dart`), which controls:

- `name` — the adapter's identifier, surfaced in `analyze` output
- `wrapHarness(String child)` — how to wrap a widget under test (e.g.
  `ProviderScope(child: ...)` for Riverpod)
- `supportsStateAwareGeneration` — whether the widget-test generator should
  emit state-aware assertions for this framework, or fall back to the
  conservative generic behaviour
- `extraImports` — additional import statements the harness needs

To add a new framework:

1. Create `lib/src/adapters/<framework>_adapter.dart` implementing
   `StateManagementAdapter` (or extending `GenericAdapter` if the fallback
   behaviour is sufficient and only the harness wrapper differs).
2. Register it in the `StateManagementAdapters.forFramework` switch in
   `state_management_adapter.dart`.
3. Add detection evidence for the framework — dependency name, `package:`
   import segment, class-inheritance match, and/or widget-usage match — to
   the state-management detector, following the existing evidence-based
   matching pattern (exact token matches, not substring matching).
4. Add a fixture under `test/fixtures/` exercising the new framework and a
   corresponding test in `test/unit/state_management_detector_test.dart`.
5. Update the state-management table in `README.md`.

## Pull Request Expectations

- One logical change per pull request.
- `dart format`, `dart analyze`, and `dart test` all pass, per Verification
  above.
- Update `CHANGELOG.md` under `[Unreleased]` describing the change.
- Update `README.md` and/or `example/README.md` if the change affects user-
  visible behaviour, commands, or output.
- No new dependency in `pubspec.yaml` without stating the reason in the pull
  request description.
- No emojis in source, comments, or documentation.

## Hard Rules

These are non-negotiable for any change to this project:

- **Never write outside `test/` and `.fluttertest_ai/`.** The tool must never
  create, modify, or delete any file under a target project's `lib/`, or any
  file outside those two locations.
- **Never add dependencies to a user's project.** FlutterTest AI must never
  modify a target project's `pubspec.yaml`.
- **Never claim a test passed unless `flutter test` actually succeeded.**
  Pass/fail counts, reports, and repair output must be derived from real
  `flutter test` results — never inferred, assumed, or hardcoded.
- **Never overwrite handwritten tests.** Only files carrying the generated
  ownership marker may be refreshed, and only when `--force` is passed.
