import '../project/dart_symbols.dart';
import '../project/models.dart';

/// Higher-level widget testability judgments used by the plan builder and
/// the widget-test generator.
class WidgetAnalyzer {
  bool isTestable(DartFileInfo file) => file.constructibleWidgets.isNotEmpty;

  /// Widgets that read inherited state (`context.watch`, `BlocBuilder`,
  /// `Obx`, ...) cannot be exercised without constructing that state, which
  /// is not safe to do automatically. Riverpod is the exception because a
  /// bare `ProviderScope` is a generic, safe harness.
  bool requiresUnsafeState(
    ClassInfo widget,
    DartFileInfo file,
    StateManagement framework,
  ) =>
      file.consumesInheritedState &&
      const {
        StateManagement.provider,
        StateManagement.bloc,
        StateManagement.getx,
        StateManagement.redux,
        StateManagement.mobx,
        StateManagement.valueNotifier,
      }.contains(framework);

  List<String> publicSignals(DartFileInfo file) => file.visibleTexts;
}
