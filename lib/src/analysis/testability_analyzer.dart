import '../project/models.dart';
import 'logic_analyzer.dart';

/// File-level confidence heuristics attached to generated test metadata and
/// included in reports. Low confidence never blocks generation of a *safe*
/// test; it only informs the review priority.
class TestabilityAnalyzer {
  TestabilityAnalyzer({LogicAnalyzer? logic})
      : _logic = logic ?? LogicAnalyzer();
  final LogicAnalyzer _logic;

  double confidence(DartFileInfo file) {
    if (file.constructibleWidgets.isNotEmpty) {
      var score = 0.65;
      if (file.visibleTexts.isNotEmpty || file.keys.isNotEmpty) score = 0.8;
      if (file.buttonTypes.isNotEmpty || file.hasTextField) score = 0.85;
      if (file.consumesInheritedState && !file.usesRiverpod) score = 0.35;
      return score;
    }
    if (file.topLevelFunctions.isNotEmpty) return 0.75;
    if (file.classDetails.any((c) =>
        c.hasFromJsonFactory || c.isChangeNotifier || c.isCubit || c.isBloc)) {
      return 0.7;
    }
    final pureClasses = _logic.pureMethodClasses(file);
    if (pureClasses.isNotEmpty) {
      // A name that follows the validator/formatter/... convention is a
      // confidence boost, not a gate: a structurally-eligible class with an
      // unconventional name (e.g. `CartTotals`) is still generated, just at
      // a slightly lower confidence than a conventionally-named one.
      return pureClasses.any(_logic.hasConventionalName) ? 0.65 : 0.55;
    }
    return 0.0;
  }
}
