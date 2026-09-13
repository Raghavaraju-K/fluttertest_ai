import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import '../project/dart_symbols.dart';
import '../project/models.dart';

class DartSourceAnalyzer {
  DartFileInfo analyze(File file) {
    final content = file.readAsStringSync();
    final result = parseString(
        content: content, path: file.path, throwIfDiagnostics: false);
    final visitor = _SourceVisitor();
    result.unit.accept(visitor);
    return DartFileInfo(
      path: file.path,
      isWidget: visitor.classDetails.any((c) => c.isWidget),
      isLogic: visitor.topLevelFunctions.isNotEmpty ||
          visitor.classDetails.any((c) => !c.isWidget),
      classes: visitor.classDetails.map((c) => c.name).toList(),
      functions: visitor.topLevelFunctions.map((f) => f.name).toList(),
      imports: visitor.imports,
      visibleTexts: visitor.visibleTexts,
      hasMaterial: visitor.hasMaterial,
      hasCupertino: visitor.hasCupertino,
      classDetails: visitor.classDetails,
      topLevelFunctions: visitor.topLevelFunctions,
      creationNames: visitor.creationNames,
      keys: visitor.keys,
      buttonTypes: visitor.buttonTypes,
      hasTextField: visitor.hasTextField,
      textFieldTypes: visitor.textFieldTypes,
      hasForm: visitor.hasForm,
      hasFormValidator: visitor.hasFormValidator,
      loadingIndicators: visitor.loadingIndicators,
      hasAsyncBuilder: visitor.hasAsyncBuilder,
      consumesInheritedState: visitor.consumesInheritedState,
      usesSetState: visitor.usesSetState,
      routeNames: visitor.routeNames,
    );
  }
}

class _SourceVisitor extends RecursiveAstVisitor<void> {
  final classDetails = <ClassInfo>[];
  final topLevelFunctions = <FunctionInfo>[];
  final imports = <String>[];
  final visibleTexts = <String>[];
  final creationNames = <String>[];
  final keys = <String>[];
  final buttonTypes = <String>[];
  final textFieldTypes = <String>[];
  final loadingIndicators = <String>[];
  final routeNames = <String>[];
  bool hasMaterial = false;
  bool hasCupertino = false;
  bool hasTextField = false;
  bool hasForm = false;
  bool hasFormValidator = false;
  bool hasAsyncBuilder = false;
  bool consumesInheritedState = false;
  bool usesSetState = false;

  @override
  void visitImportDirective(ImportDirective node) {
    imports.add(node.uri.stringValue ?? '');
    super.visitImportDirective(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final className = node.name.lexeme;
    final superclassName = node.extendsClause?.superclass.name2.lexeme ?? '';
    final widgetSuperkinds = {
      'StatelessWidget': 'StatelessWidget',
      'StatefulWidget': 'StatefulWidget',
      'ConsumerWidget': 'ConsumerWidget',
      'ConsumerStatefulWidget': 'ConsumerStatefulWidget',
      'HookWidget': 'HookWidget',
      'HookConsumerWidget': 'HookConsumerWidget',
      'GetView': 'GetView',
    };
    final widgetSuperkind = widgetSuperkinds[superclassName];
    final isAbstract = node.abstractKeyword != null;
    final constructors = <ConstructorInfo>[];
    final methods = <FunctionInfo>[];
    var hasFromJsonFactory = false;
    for (final member in node.members) {
      if (member is ConstructorDeclaration) {
        if (member.factoryKeyword != null &&
            member.name?.lexeme == 'fromJson') {
          hasFromJsonFactory = true;
        }
        final params = <ParameterInfo>[];
        for (final p in member.parameters.parameters) {
          params.add(_parameterInfo(p));
        }
        constructors.add(ConstructorInfo(
            member.name?.lexeme, params, member.constKeyword != null));
      } else if (member is MethodDeclaration) {
        final methodName = member.name.lexeme;
        if (member.isStatic &&
            methodName == 'fromJson' &&
            member.returnType != null) {
          hasFromJsonFactory = true;
        }
        if (methodName.startsWith('_')) continue;
        final params = <ParameterInfo>[];
        if (member.parameters != null) {
          for (final p in member.parameters!.parameters) {
            params.add(_parameterInfo(p));
          }
        }
        methods.add(FunctionInfo(
          name: methodName,
          returnTypeSource: member.returnType?.toString() ?? 'dynamic',
          parameters: params,
          isStatic: member.isStatic,
          isGetter: member.isGetter,
          isSetter: member.isSetter,
        ));
      }
    }
    classDetails.add(ClassInfo(
      name: className,
      superclassName: superclassName,
      isAbstract: isAbstract,
      widgetSuperkind: widgetSuperkind,
      constructors: constructors,
      methods: methods,
      isChangeNotifier:
          _ext(superclassName, ['ChangeNotifier', 'ValueNotifier']),
      isCubit: _ext(superclassName, ['Cubit', 'BlocCubit']),
      isBloc: _ext(superclassName, ['Bloc', 'BlocBase']),
      isStateNotifier: _ext(superclassName, ['StateNotifier']),
      hasFromJsonFactory: hasFromJsonFactory,
    ));
    super.visitClassDeclaration(node);
  }

  bool _ext(String d, List<String> c) => c.contains(d);

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.isGetter || node.isSetter) {
      super.visitFunctionDeclaration(node);
      return;
    }
    final params = <ParameterInfo>[];
    final funcParams = node.functionExpression.parameters?.parameters;
    if (funcParams != null) {
      for (final p in funcParams) {
        params.add(_parameterInfo(p));
      }
    }
    topLevelFunctions.add(FunctionInfo(
      name: node.name.lexeme,
      returnTypeSource: node.returnType?.toString() ?? 'dynamic',
      parameters: params,
      isStatic: false,
    ));
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _recordCreation(
        node.constructorName.type.name2.lexeme, node.argumentList, node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    if (methodName == 'setState') usesSetState = true;
    if (methodName == 'watch' || methodName == 'read') {
      consumesInheritedState = true;
    }
    // Without a resolved element model, a bare (no `const`/`new`, no
    // receiver) call to a PascalCase identifier is syntactically
    // indistinguishable from a constructor invocation at parse time — the
    // analyzer's unresolved AST hands these to visitMethodInvocation, not
    // visitInstanceCreationExpression, unlike `const Foo()`/`new Foo()`.
    // Widgets are overwhelmingly constructed this way in real code (any
    // constructor argument that isn't itself a compile-time constant, e.g.
    // an instance-method tear-off callback, forces the call to be
    // non-const), so treating this as a widget-name signal too is required
    // for buttonTypes/hasForm/hasTextField/loadingIndicators/hasMaterial to
    // work outside of purely-const widget trees.
    if (node.target == null && _looksLikeTypeName(methodName)) {
      _recordCreation(methodName, node.argumentList, node);
    }
    super.visitMethodInvocation(node);
  }

  bool _looksLikeTypeName(String name) =>
      name.isNotEmpty &&
      name.codeUnitAt(0) >= 0x41 &&
      name.codeUnitAt(0) <= 0x5A;

  void _recordCreation(String name, ArgumentList argumentList, AstNode node) {
    creationNames.add(name);
    if (const {
      'MaterialApp',
      'Scaffold',
      'Text',
      'AppBar',
      'FloatingActionButton'
    }.contains(name)) {
      hasMaterial = true;
    }
    if (name == 'CupertinoApp' || name.startsWith('Cupertino')) {
      hasCupertino = true;
    }

    // Every signal below is asserted by the widget-test generator as
    // unconditionally present on first paint (`findsOneWidget` /
    // `findsWidgets` immediately after the first `pump()`). A node whose
    // build is gated by a branch, loop, or null-coalescing operator is not
    // guaranteed to exist at that point — e.g. `if (_submitted)
    // Text('Signed in')` never builds on the initial (false) state — so it
    // must not feed one of those signals. `hasAsyncBuilder` is excluded from
    // this gating: it only drives an advisory note, never a `find.*`
    // assertion, so its accuracy as "a FutureBuilder/StreamBuilder exists
    // somewhere in this file" is unaffected by where it is built.
    final isConditional = _isConditionallyBuilt(node);

    if (!isConditional &&
        const {
          'ElevatedButton',
          'TextButton',
          'OutlinedButton',
          'FilledButton',
          'IconButton',
          'FloatingActionButton'
        }.contains(name)) {
      buttonTypes.add(name);
    }
    if (!isConditional && (name == 'TextField' || name == 'TextFormField')) {
      hasTextField = true;
      textFieldTypes.add(name);
    }
    if (!isConditional && name == 'Form') hasForm = true;
    if (!isConditional &&
        const {'LinearProgressIndicator', 'CircularProgressIndicator'}
            .contains(name)) {
      loadingIndicators.add(name);
    }
    if (name == 'FutureBuilder' || name == 'StreamBuilder') {
      hasAsyncBuilder = true;
    }
    if (!isConditional && name == 'Text') {
      for (final argument in argumentList.arguments) {
        if (argument is StringLiteral &&
            argument.stringValue != null &&
            argument.stringValue!.isNotEmpty) {
          visibleTexts.add(argument.stringValue!);
          break;
        }
      }
    }
    if (!isConditional &&
        name == 'ValueKey' &&
        argumentList.arguments.isNotEmpty) {
      final first = argumentList.arguments.first;
      if (first is StringLiteral && first.stringValue != null) {
        keys.add(first.stringValue!);
      }
    }
  }

  /// Walks up from a candidate creation node to the enclosing function/method
  /// body, returning `true` if any ancestor in between makes the node's
  /// construction conditional on runtime state rather than guaranteed on
  /// first build.
  ///
  /// Stops at the first [FunctionBody] so it never escapes into an unrelated
  /// enclosing method/function (e.g. a sibling `build()` on the same class).
  /// A loop is treated as conditional because its body may execute zero
  /// times; a null-aware spread (`...?`) is treated as conditional because
  /// the spread source may be null, contributing no elements.
  bool _isConditionallyBuilt(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is FunctionBody) return false;
      if (current is IfStatement ||
          current is IfElement ||
          current is ConditionalExpression ||
          current is SwitchStatement ||
          current is SwitchExpression ||
          current is ForStatement ||
          current is ForElement ||
          current is WhileStatement ||
          current is DoStatement) {
        return true;
      }
      if (current is SpreadElement && current.isNullAware) return true;
      if (current is BinaryExpression &&
          current.operator.type == TokenType.QUESTION_QUESTION) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }
}

/// Builds a [ParameterInfo] from a [FormalParameter], extracting only the
/// declared type (never the parameter name) so downstream literal synthesis
/// can match it exactly.
ParameterInfo _parameterInfo(FormalParameter p) {
  final type = _resolveParameterType(p);
  return ParameterInfo(
    name: p.name?.lexeme ?? '',
    typeSource: type.source,
    isRequiredPositional: p.isPositional && p.isRequired,
    isRequiredNamed: p.isNamed && p.isRequired,
    isNullable: type.isNullable,
  );
}

class _ParameterType {
  const _ParameterType(this.source, this.isNullable);
  final String source;
  final bool isNullable;
}

/// Resolves the declared type of a [FormalParameter] using only AST
/// properties, unwrapping [DefaultFormalParameter] (optional/named
/// parameters) to reach the underlying [NormalFormalParameter] shape.
_ParameterType _resolveParameterType(FormalParameter parameter) {
  final normal =
      parameter is DefaultFormalParameter ? parameter.parameter : parameter;

  if (normal is SimpleFormalParameter) {
    final type = normal.type;
    // A plain untyped parameter (`f(x)`) is genuinely `dynamic` in Dart.
    if (type == null) return const _ParameterType('dynamic', false);
    return _fromTypeAnnotation(type);
  }
  if (normal is FieldFormalParameter) {
    final type = normal.type;
    if (type != null) return _fromTypeAnnotation(type);
    // `this.x` without an explicit type is inferred from the field
    // declaration, which this visitor does not resolve; treat as unknown
    // rather than guessing a literal.
    if (normal.parameters != null) {
      return _ParameterType('Function', normal.question != null);
    }
    return const _ParameterType('unknown', false);
  }
  if (normal is SuperFormalParameter) {
    final type = normal.type;
    if (type != null) return _fromTypeAnnotation(type);
    if (normal.parameters != null) {
      return _ParameterType('Function', normal.question != null);
    }
    return const _ParameterType('unknown', false);
  }
  if (normal is FunctionTypedFormalParameter) {
    return _ParameterType('Function', normal.question != null);
  }
  return const _ParameterType('unknown', false);
}

_ParameterType _fromTypeAnnotation(TypeAnnotation type) {
  final source = type.toSource().replaceAll(RegExp(r'\s+'), ' ').trim();
  return _ParameterType(source, source.endsWith('?'));
}
