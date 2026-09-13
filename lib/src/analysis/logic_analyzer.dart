import '../project/dart_symbols.dart';
import '../project/models.dart';

/// Selects conservative unit-test targets from analyzed files.
class LogicAnalyzer {
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

  /// Utility classes whose instance methods are likely pure: validators,
  /// formatters, mappers, converters, parsers, helpers, and calculators.
  List<ClassInfo> pureMethodClasses(DartFileInfo file) {
    final pattern = RegExp(
        r'(Validator|Formatter|Mapper|Converter|Parser|Helper|Calculator|Utils?|Tools?)$');
    return file.classDetails
        .where((c) => c.isPubliclyConstructible && pattern.hasMatch(c.name))
        .toList();
  }
}
