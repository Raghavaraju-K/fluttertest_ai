import 'dart:convert';

import 'dart_symbols.dart';

enum StateManagement {
  setState,
  provider,
  riverpod,
  bloc,
  getx,
  redux,
  mobx,
  valueNotifier,
  signals,
  unknown,
}

/// Human-friendly labels for reports and console output.
extension StateManagementLabel on StateManagement {
  String get label => switch (this) {
        StateManagement.provider => 'Provider / ChangeNotifier',
        StateManagement.riverpod => 'Riverpod',
        StateManagement.bloc => 'BLoC / Cubit',
        StateManagement.getx => 'GetX',
        StateManagement.redux => 'Redux',
        StateManagement.mobx => 'MobX',
        StateManagement.valueNotifier => 'ValueNotifier',
        StateManagement.signals => 'Signals',
        StateManagement.setState => 'setState',
        StateManagement.unknown => 'Unknown / custom',
      };
}

class Evidence {
  const Evidence(this.kind, this.value);
  final String kind;
  final String value;
  Map<String, Object> toJson() => {'kind': kind, 'value': value};
}

class StateManagementResult {
  const StateManagementResult({
    required this.framework,
    required this.confidence,
    required this.evidence,
    required this.adapter,
  });
  final StateManagement framework;
  final double confidence;
  final List<Evidence> evidence;
  final String adapter;
  Map<String, Object> toJson() => {
        'framework': framework.name,
        'confidence': confidence,
        'evidence': [for (final e in evidence) e.toJson()],
        'adapter': adapter,
      };
}

/// Everything the AST analyzer learned about one Dart file.
class DartFileInfo {
  const DartFileInfo({
    required this.path,
    required this.isWidget,
    required this.isLogic,
    required this.classes,
    required this.functions,
    required this.imports,
    required this.visibleTexts,
    required this.hasMaterial,
    required this.hasCupertino,
    required this.classDetails,
    required this.topLevelFunctions,
    required this.creationNames,
    required this.keys,
    required this.buttonTypes,
    required this.hasTextField,
    required this.textFieldTypes,
    required this.hasForm,
    required this.hasFormValidator,
    required this.loadingIndicators,
    required this.hasAsyncBuilder,
    required this.consumesInheritedState,
    required this.usesSetState,
    required this.routeNames,
  });

  /// Absolute path of the analyzed file.
  final String path;
  final bool isWidget;
  final bool isLogic;
  final List<String> classes;
  final List<String> functions;
  final List<String> imports;
  final List<String> visibleTexts;
  final bool hasMaterial;
  final bool hasCupertino;

  /// Per-class symbol details (superclass, constructors, methods, ...).
  final List<ClassInfo> classDetails;
  final List<FunctionInfo> topLevelFunctions;

  /// Every instance-creation name found in the file, e.g. `BlocBuilder`.
  final List<String> creationNames;
  final List<String> keys;
  final List<String> buttonTypes;
  final bool hasTextField;
  final List<String> textFieldTypes;
  final bool hasForm;
  final bool hasFormValidator;
  final List<String> loadingIndicators;
  final bool hasAsyncBuilder;
  final bool consumesInheritedState;
  final bool usesSetState;
  final List<String> routeNames;

  /// Whether the file imports Riverpod from any of its packages.
  bool get usesRiverpod => imports.any((uri) =>
      uri.startsWith('package:flutter_riverpod/') ||
      uri.startsWith('package:hooks_riverpod/') ||
      uri.startsWith('package:riverpod/'));

  /// High-level classification used by `analyze` and reports.
  List<String> get kinds {
    final names = [...classes, ...functions];
    final result = <String>[
      if (isWidget) 'widget',
      if (isLogic) 'logic',
    ];
    void addWhen(String kind, bool condition) {
      if (condition && !result.contains(kind)) result.add(kind);
    }

    addWhen('validator', names.any((n) => n.toLowerCase().contains('valid')));
    addWhen('formatter', names.any((n) => n.toLowerCase().contains('format')));
    addWhen('service', names.any((n) => n.contains('Service')));
    addWhen(
        'repository',
        names.any((n) =>
            n.contains('Repository') || n.toLowerCase().contains('repo')));
    addWhen(
        'model',
        classDetails.any((c) => c.hasFromJsonFactory) ||
            names.any((n) => n.contains('Model')));
    addWhen(
        'state class',
        classDetails.any((c) =>
            c.isChangeNotifier ||
            c.isCubit ||
            c.isBloc ||
            c.isStateNotifier ||
            c.name.endsWith('Notifier') ||
            c.name.endsWith('Store')));
    addWhen(
        'route',
        routeNames.isNotEmpty ||
            names.any((n) => n.contains('Route') || n.contains('Router')));
    return result;
  }

  /// Public widget classes that can be safely constructed as `Widget()`.
  List<ClassInfo> get constructibleWidgets => classDetails
      .where((c) => c.isWidget && c.isPubliclyConstructible)
      .toList();
}

class ProjectAnalysis {
  const ProjectAnalysis({
    required this.root,
    required this.projectName,
    required this.files,
    required this.stateManagement,
    required this.existingTests,
    required this.skipped,
    this.dependencies = const [],
  });
  final String root;
  final String projectName;
  final List<DartFileInfo> files;
  final StateManagementResult stateManagement;
  final List<String> existingTests;
  final List<String> skipped;

  /// Dependency names from pubspec (dependencies + dev_dependencies).
  final List<String> dependencies;

  int get widgetCount => files.where((f) => f.isWidget).length;
  int get logicCount => files.where((f) => f.isLogic && !f.isWidget).length;
  int get testableClassCount => files.fold<int>(
      0, (total, f) => total + f.classDetails.where((c) => c.isPublic).length);

  Map<String, Object> toJson() => {
        'projectName': projectName,
        'dependencies': dependencies,
        'files': [for (final f in files) f.path],
        'widgets': widgetCount,
        'logicFiles': logicCount,
        'testableClasses': testableClassCount,
        'stateManagement': stateManagement.toJson(),
        'existingTests': existingTests,
        'skipped': skipped,
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
