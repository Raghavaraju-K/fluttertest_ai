# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Raghavaraju-K/fluttertest_ai/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Raghavaraju-K/fluttertest_ai/releases/tag/v0.1.0

