import '../generation/value_fixtures.dart';
import '../project/dart_symbols.dart';
import '../project/models.dart';

/// A structurally-eligible class excluded from [LogicAnalyzer.pureMethodClasses]
/// because it strongly suggests external I/O, paired with a human-readable
/// explanation for reports.
class IoSkippedClass {
  const IoSkippedClass(this.name, this.reason);
  final String name;
  final String reason;
}

/// Selects conservative unit-test targets from analyzed files.
class LogicAnalyzer {
  LogicAnalyzer({ValueFixtures? values})
      : _values = values ?? const ValueFixtures();
  final ValueFixtures _values;

  bool isTestable(DartFileInfo file) =>
      unitFunctions(file).isNotEmpty ||
      lifecycleClasses(file).isNotEmpty ||
      serializableClasses(file).isNotEmpty ||
      pureMethodClasses(file).isNotEmpty;

  /// Public top-level functions callable without any setup.
  List<FunctionInfo> unitFunctions(DartFileInfo file) => file.topLevelFunctions
      .where(
          (f) => f.name != 'main' && !f.name.startsWith('_') && !f.isOperator)
      .toList();

  /// State containers with safe lifecycle smoke tests (construct + dispose).
  List<ClassInfo> lifecycleClasses(DartFileInfo file) => file.classDetails
      .where((c) =>
          c.isPubliclyConstructible &&
          (c.isChangeNotifier || c.isCubit || c.isBloc || c.isStateNotifier))
      .toList();

  /// Classes with a `fromJson` factory; exercised with a tolerant test that
  /// accepts either a successful parse or a deliberate rejection.
  List<ClassInfo> serializableClasses(DartFileInfo file) => file.classDetails
      .where((c) => c.isPublic && c.hasFromJsonFactory)
      .toList();

  /// Plain classes whose public surface is structurally safe to call from a
  /// generated unit test: publicly constructible (so no dependencies need to
  /// be injected), not a Flutter widget, and exposing at least one public,
  /// synchronous, non-operator instance method, static method, or getter
  /// whose required parameters can all be synthesized by [ValueFixtures].
  ///
  /// Eligibility is purely structural — a class name is no longer a gate,
  /// only a confidence signal (see [hasConventionalName]). Classes that
  /// qualify structurally but strongly suggest external I/O are excluded
  /// here and reported instead via [ioSkippedClasses].
  List<ClassInfo> pureMethodClasses(DartFileInfo file) {
    final hasIoImport = _fileHasIoImport(file);
    return file.classDetails
        .where((c) =>
            _isStructurallyEligible(c) && !_looksLikeIo(c.name) && !hasIoImport)
        .toList();
  }

  /// Structurally-eligible classes excluded from [pureMethodClasses] because
  /// their name or the file's imports strongly suggest external I/O (a
  /// service, repository, HTTP/database client, ...). Calling their methods
  /// in a generated test risks flaky failures or real side effects, so they
  /// are skipped with a recorded, reportable reason instead.
  List<IoSkippedClass> ioSkippedClasses(DartFileInfo file) {
    final hasIoImport = _fileHasIoImport(file);
    final result = <IoSkippedClass>[];
    for (final c in file.classDetails) {
      if (!_isStructurallyEligible(c)) continue;
      final nameSuggestsIo = _looksLikeIo(c.name);
      if (!nameSuggestsIo && !hasIoImport) continue;
      result.add(IoSkippedClass(
        c.name,
        nameSuggestsIo
            ? 'name suggests external I/O (matches Service/Repository/'
                'Client/Api/Http/Database/Db/Gateway/DataSource)'
            : 'file imports an I/O package (dart:io, http, dio, '
                'shared_preferences, sqflite, firebase, or ffi)',
      ));
    }
    return result;
  }

  /// Whether [c]'s name matches the conventional utility-class naming
  /// convention (validator, formatter, mapper, converter, parser, helper,
  /// calculator, utils, tools). This is only a confidence signal now, never
  /// a gate on eligibility.
  bool hasConventionalName(ClassInfo c) =>
      _conventionalNamePattern.hasMatch(c.name);

  bool _isStructurallyEligible(ClassInfo c) =>
      c.isPubliclyConstructible &&
      !c.isWidget &&
      c.methods.any(_isQualifyingMethod);

  bool _isQualifyingMethod(FunctionInfo m) {
    if (m.isOperator || m.isAsynchronous || m.isSetter) return false;
    if (m.isGetter) return true;
    final required = m.requiredParameters;
    if (required.length > 3) return false;
    return required.every(_values.isSupported);
  }

  bool _looksLikeIo(String name) => _ioNamePattern.hasMatch(name);

  bool _fileHasIoImport(DartFileInfo file) =>
      file.imports.any((uri) => _ioImportHints.any(uri.contains));

  static final RegExp _conventionalNamePattern = RegExp(
      r'(Validator|Formatter|Mapper|Converter|Parser|Helper|Calculator|Utils?|Tools?)$');

  /// Matches a class name that starts or ends with a common I/O-suggesting
  /// word, e.g. `UserRepository`, `HttpClient`, `ApiGateway`.
  static final RegExp _ioNamePattern = RegExp(
      r'^(?:Service|Repository|Client|Api|Http|Database|Db|Gateway|DataSource)'
      r'|(?:Service|Repository|Client|Api|Http|Database|Db|Gateway|DataSource)$');

  static const List<String> _ioImportHints = [
    'dart:io',
    'dart:ffi',
    'package:http/',
    'package:dio/',
    'shared_preferences',
    'sqflite',
    'firebase',
  ];
}
