import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../project/dart_symbols.dart';
import '../project/models.dart';

/// AST-based source inspection.
///
/// Files with syntax errors are still parsed (with `throwIfDiagnostics:
/// false`) and may produce partial results; read failures are surfaced to the
/// caller, which records the file as skipped.
class DartSourceAnalyzer {
  DartFileInfo analyze(File file) {
    final result = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    final visitor = _SourceVisitor();
    result.unit.accept(visitor);
    final isRiverpodFile = visitor.imports.any((uri) =>
        uri.startsWith('package:flutter_riverpod/') ||
        uri.startsWith('package:hooks_riverpod/') ||
        uri.startsWith('package:riverpod/'));
    return DartFileInfo(
      path: file.path,
      isWidget: visitor.collectedClasses.any((c) => c.isWidget),
      isLogic: visitor.topLevelFunctions.isNotEmpty ||
          (visitor.collectedClasses.isNotEmpty &&
              !visitor.collectedClasses.any((c) => c.isWidget)),
      classes: [for (final c in visitor.collectedClasses) c.name],
      functions: [for (final f in visitor.topLevelFunctions) f.name],
      imports: List.unmodifiable(visitor.imports),
      visibleTexts: List.unmodifiable(visitor.visibleTexts),
      hasMaterial: visitor.hasMaterial,
      hasCupertino: visitor.hasCupertino,
      classDetails: List.unmodifiable(visitor.collectedClasses),
      topLevelFunctions: List.unmodifiable(visitor.topLevelFunctions),
      creationNames: List.unmodifiable(visitor.creationNames),
      keys: List.unmodifiable(visitor.keys),
      buttonTypes: List.unmodifiable(visitor.buttonTypes),
      hasTextField: visitor.textFieldTypes.isNotEmpty,
      textFieldTypes: List.unmodifiable(visitor.textFieldTypes),
      hasForm: visitor.hasForm,
      hasFormValidator: visitor.hasFormValidator,
      loadingIndicators: List.unmodifiable(visitor.loadingIndicators),
      hasAsyncBuilder: visitor.hasAsyncBuilder,
      consumesInheritedState: visitor.consumesInheritedState(isRiverpodFile),
      usesSetState: visitor.usesSetState,
      routeNames: List.unmodifiable(visitor.routeNames),
    );
  }
}

class _SourceVisitor extends RecursiveAstVisitor<void> {
  final imports = <String>[];
  final visibleTexts = <String>[];
  final creationNames = <String>[];
  final keys = <String>[];
  final buttonTypes = <String>[];
  final loadingIndicators = <String>[];
  final routeNames = <String>[];
  final topLevelFunctions = <FunctionInfo>[];
  final collectedClasses = <ClassInfo>[];
  final consumerCreations = <String>[];

  bool hasMaterial = false;
  bool hasCupertino = false;
  final textFieldTypes = <String>[];
  bool hasForm = false;
  bool hasFormValidator = false;
  bool hasAsyncBuilder = false;
  bool usesSetState = false;
  bool contextOrRefStateRead = false;

  String? _currentClass;
  List<ConstructorInfo> _classConstructors = const [];
  List<FunctionInfo> _classMethods = const [];

  @override
  void visitImportDirective(ImportDirective node) {
    imports.add(node.uri.stringValue ?? '');
    super.visitImportDirective(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    if (_currentClass == null && !node.isGetter && !node.isSetter) {
      topLevelFunctions.add(FunctionInfo(
        name: name,
        returnTypeSource: node.returnType?.toSource() ?? 'dynamic',
        parameters: _parameters(node.functionExpression.parameters),
        isStatic: false,
      ));
      if (const {'onGenerateRoute', 'onUnknownRoute', 'generateRoute'}
          .contains(name)) {
        routeNames.add(name);
      }
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final superclass = node.extendsClause?.superclass.name2.lexeme ?? '';
    final savedClass = _currentClass;
    final savedConstructors = _classConstructors;
    final savedMethods = _classMethods;
    final constructors = <ConstructorInfo>[];
    final methods = <FunctionInfo>[];
    _currentClass = node.name.lexeme;
    _classConstructors = constructors;
    _classMethods = methods;
    super.visitClassDeclaration(node);
    _currentClass = savedClass;
    _classConstructors = savedConstructors;
    _classMethods = savedMethods;
    final name = node.name.lexeme;
    if (name.contains('Route') || name.contains('Router')) routeNames.add(name);
    // Classes with no explicit constructor have an implicit default
    // constructor: treat it as a public unnamed constructor with no
    // required parameters so utility classes (validators, formatters,
    // etc.) are recognized as constructible.
    if (constructors.isEmpty) {
      constructors.add(ConstructorInfo(null, const [], false));
    }
    collectedClasses.add(ClassInfo(
      name: name,
      superclassName: superclass,
      isAbstract: node.abstractKeyword != null,
      widgetSuperkind: _widgetSuperkind(superclass),
      constructors: List.unmodifiable(constructors),
      methods: List.unmodifiable(methods),
      isChangeNotifier: superclass == 'ChangeNotifier',
      isCubit: superclass == 'Cubit',
      isBloc: superclass == 'Bloc',
      isStateNotifier: superclass == 'StateNotifier',
      hasFromJsonFactory: constructors.any((c) => c.name == 'fromJson'),
    ));
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (_currentClass != null) {
      _classConstructors.add(ConstructorInfo(
        node.name?.lexeme,
        _parameters(node.parameters),
        node.constKeyword != null,
      ));
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (_currentClass != null &&
        !node.isGetter &&
        !node.isSetter &&
        RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name)) {
      _classMethods.add(FunctionInfo(
        name: name,
        returnTypeSource: node.returnType?.toSource() ?? 'dynamic',
        parameters: _parameters(node.parameters),
        isStatic: node.isStatic,
      ));
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.token.lexeme;
    if (name == 'setState') usesSetState = true;
    final target = node.target;
    if (target is SimpleIdentifier) {
      final receiver = target.token.lexeme;
      if ((receiver == 'context' || receiver == 'ref') &&
          const {'watch', 'read', 'select', 'listen'}.contains(name)) {
        contextOrRefStateRead = true;
      }
      if (receiver == 'Provider' && name == 'of') contextOrRefStateRead = true;
    } else if (target == null && _looksLikeConstructorName(name)) {
      // The analyzer parses un-targeted calls like `Scaffold(...)` as
      // MethodInvocation (not InstanceCreationExpression) when they are
      // not preceded by `const` or `new`. Recognise them here so that
      // widget detection still picks them up.
      _recordCreation(name, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name2.lexeme;
    _recordCreation(name, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  /// Records every widget/constructor signal for [name] invoked with
  /// [arguments]. Shared between [visitInstanceCreationExpression] (const
  /// and `new` invocations) and [visitMethodInvocation] (bare invocations
  /// like `Scaffold(...)` which the analyzer emits as MethodInvocation).
  void _recordCreation(String name, ArgumentList arguments) {
    creationNames.add(name);
    if (name.startsWith('Cupertino')) hasCupertino = true;
    if (_materialNames.contains(name)) hasMaterial = true;
    if (_buttonNames.contains(name)) buttonTypes.add(name);
    if (_textFieldNames.contains(name)) textFieldTypes.add(name);
    if (name == 'Form') hasForm = true;
    if (arguments.arguments.any((argument) =>
        argument is NamedExpression &&
        argument.name.beginToken.lexeme == 'validator')) {
      hasFormValidator = true;
    }
    if (_loadingNames.contains(name)) loadingIndicators.add(name);
    if (_asyncBuilderNames.contains(name)) hasAsyncBuilder = true;
    if (_consumerNames.contains(name)) consumerCreations.add(name);
    if (const {'Key', 'ValueKey', 'ObjectKey'}.contains(name)) {
      for (final argument in arguments.arguments) {
        if (argument is StringLiteral) {
          final value = argument.stringValue;
          if (value != null) keys.add(value);
          break;
        }
      }
    }
    if (name == 'Text') {
      for (final argument in arguments.arguments) {
        if (argument is StringLiteral) {
          final value = argument.stringValue;
          if (value != null) visibleTexts.add(value);
          break;
        }
      }
      for (final argument in arguments.arguments) {
        if (argument is NamedExpression &&
            argument.name.beginToken.lexeme == 'data' &&
            argument.expression is StringLiteral) {
          final value = (argument.expression as StringLiteral).stringValue;
          if (value != null) visibleTexts.add(value);
        }
      }
    }
  }

  /// Returns true when [name] looks like a constructor invocation rather
  /// than a regular method call: it starts with an uppercase letter.
  static bool _looksLikeConstructorName(String name) {
    if (name.isEmpty) return false;
    final first = name.codeUnitAt(0);
    return first >= 0x41 && first <= 0x5A; // A–Z
  }

  /// A widget reads inherited state when it watches context/ref, uses
  /// `Provider.of`, or builds through a stateful builder widget. Riverpod's
  /// `Consumer` is excluded for Riverpod files: `ProviderScope` covers it.
  bool consumesInheritedState(bool isRiverpodFile) {
    if (contextOrRefStateRead && !isRiverpodFile) return true;
    for (final name in consumerCreations) {
      if (name == 'Consumer') {
        if (!isRiverpodFile) return true;
      } else {
        return true;
      }
    }
    return false;
  }

  String? _widgetSuperkind(String superclass) => const {
        'StatelessWidget',
        'StatefulWidget',
        'ConsumerWidget',
        'ConsumerStatefulWidget',
        'HookWidget',
        'HookConsumerWidget',
        'GetView',
      }.contains(superclass)
          ? superclass
          : null;

  static const _materialNames = {
    'MaterialApp',
    'Scaffold',
    'AppBar',
    'Text',
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'IconButton',
    'FloatingActionButton',
    'TextField',
    'TextFormField',
    'Form',
    'CircularProgressIndicator',
    'LinearProgressIndicator',
    'Column',
    'Row',
    'Container',
    'Center',
    'Padding',
    'Card',
    'ListTile',
    'TabBar',
    'Drawer',
    'BottomNavigationBar',
  };
  static const _buttonNames = {
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'IconButton',
    'FloatingActionButton',
    'CupertinoButton',
    'DropdownButton',
    'PopupMenuButton',
    'BackButton',
    'CloseButton',
  };
  static const _textFieldNames = {
    'TextField',
    'TextFormField',
    'CupertinoTextField',
    'CupertinoTextFormFieldRow',
  };
  static const _loadingNames = {
    'CircularProgressIndicator',
    'LinearProgressIndicator',
    'CupertinoActivityIndicator',
  };
  static const _asyncBuilderNames = {'FutureBuilder', 'StreamBuilder'};
  static const _consumerNames = {
    'BlocBuilder',
    'BlocConsumer',
    'BlocListener',
    'GetBuilder',
    'Obx',
    'StoreConnector',
    'Observer',
    'ValueListenableBuilder',
    'Consumer',
  };
}

List<ParameterInfo> _parameters(FormalParameterList? list) {
  if (list == null) return const [];
  return [
    for (final prm in list.parameters)
      ParameterInfo(
        name: prm.name?.lexeme ?? '',
        typeSource: _typeSource(prm),
        isRequiredPositional: prm.isRequiredPositional,
        isRequiredNamed: prm.isRequiredNamed,
        isNullable: _typeSource(prm).endsWith('?'),
      ),
  ];
}

String _typeSource(FormalParameter prm) {
  final inner = prm is DefaultFormalParameter ? prm.parameter : prm;
  if (inner is SimpleFormalParameter) {
    return inner.type?.toSource() ?? 'dynamic';
  }
  if (inner is FunctionTypedFormalParameter) return 'Function';
  if (inner is SuperFormalParameter) return 'super';
  return 'dynamic';
}
