/// Lightweight, analyzer-derived symbol information consumed by the
/// test generators. These models intentionally avoid resolved elements so
/// generation works without a full analysis context.
library;

class ParameterInfo {
  const ParameterInfo({
    required this.name,
    required this.typeSource,
    required this.isRequiredPositional,
    required this.isRequiredNamed,
    required this.isNullable,
  });

  final String name;
  final String typeSource;
  final bool isRequiredPositional;
  final bool isRequiredNamed;
  final bool isNullable;

  bool get isRequired => isRequiredPositional || isRequiredNamed;
}

class FunctionInfo {
  const FunctionInfo({
    required this.name,
    required this.returnTypeSource,
    required this.parameters,
    required this.isStatic,
    this.isGetter = false,
    this.isSetter = false,
  });

  final String name;
  final String returnTypeSource;
  final List<ParameterInfo> parameters;
  final bool isStatic;
  final bool isGetter;
  final bool isSetter;

  bool get isAsynchronous =>
      returnTypeSource.startsWith('Future') ||
      returnTypeSource.startsWith('Stream');

  bool get isOperator => !RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name);

  List<ParameterInfo> get requiredParameters =>
      parameters.where((prm) => prm.isRequired).toList();

  bool get hasNullableParameter => parameters.any((prm) => prm.isNullable);
}

class ConstructorInfo {
  const ConstructorInfo(this.name, this.parameters, this.isConst);

  /// `null` for the unnamed constructor.
  final String? name;
  final List<ParameterInfo> parameters;
  final bool isConst;

  bool get isUnnamed => name == null;

  bool get hasRequiredParameters => parameters.any((prm) => prm.isRequired);
}

class ClassInfo {
  const ClassInfo({
    required this.name,
    required this.superclassName,
    required this.isAbstract,
    required this.widgetSuperkind,
    required this.constructors,
    required this.methods,
    required this.isChangeNotifier,
    required this.isCubit,
    required this.isBloc,
    required this.isStateNotifier,
    required this.hasFromJsonFactory,
  });

  final String name;

  /// Lexeme of the superclass when present (base name only).
  final String superclassName;
  final bool isAbstract;

  /// One of StatelessWidget, StatefulWidget, ConsumerWidget,
  /// ConsumerStatefulWidget, HookWidget, HookConsumerWidget, GetView,
  /// or null for non-widget classes.
  final String? widgetSuperkind;
  final List<ConstructorInfo> constructors;
  final List<FunctionInfo> methods;
  final bool isChangeNotifier;
  final bool isCubit;
  final bool isBloc;
  final bool isStateNotifier;
  final bool hasFromJsonFactory;

  bool get isPublic => !name.startsWith('_');

  bool get isWidget => widgetSuperkind != null;

  ConstructorInfo? get unnamedConstructor {
    for (final ctor in constructors) {
      if (ctor.isUnnamed) return ctor;
    }
    return null;
  }

  /// True when `ClassName()` is a safe, complete call: a public unnamed
  /// constructor without required parameters.
  ///
  /// A class with no declared constructors at all gets an implicit,
  /// no-arg public unnamed constructor from Dart itself, so an empty
  /// [constructors] list is safely constructible too. A class that only
  /// declares a named or private constructor is not.
  bool get isPubliclyConstructible {
    if (!isPublic || isAbstract) return false;
    if (constructors.isEmpty) return true;
    final ctor = unnamedConstructor;
    return ctor != null && !ctor.hasRequiredParameters;
  }
}
