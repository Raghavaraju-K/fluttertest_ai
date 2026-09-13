import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import '../project/dart_symbols.dart';
import '../project/models.dart';

class DartSourceAnalyzer {
  DartFileInfo analyze(File file) {
    final content = file.readAsStringSync();
    final result = parseString(content: content, path: file.path, throwIfDiagnostics: false);
    final visitor = _SourceVisitor();
    result.unit.accept(visitor);
    return DartFileInfo(
      path: file.path,
      isWidget: visitor.classDetails.any((c) => c.isWidget),
      isLogic: visitor.topLevelFunctions.isNotEmpty || visitor.classDetails.any((c) => !c.isWidget),
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
        final params = <ParameterInfo>[];
        for (final p in member.parameters.parameters) {
          final typeStr = p.toString();
          params.add(ParameterInfo(
            name: p.name?.lexeme ?? '',
            typeSource: typeStr,
            isRequiredPositional: p.isPositional && p.isRequired,
            isRequiredNamed: p.isNamed && p.isRequired,
            isNullable: typeStr.endsWith('?'),
          ));
        }
        constructors.add(ConstructorInfo(member.name?.lexeme, params, member.constKeyword != null));
      } else if (member is MethodDeclaration) {
        final methodName = member.name.lexeme;
        if (member.isStatic && methodName == 'fromJson' && member.returnType != null) {
          hasFromJsonFactory = true;
        }
        if (member.isStatic) continue;
        final params = <ParameterInfo>[];
        if (member.parameters != null) {
          for (final p in member.parameters!.parameters) {
            final typeStr = p.toString();
            params.add(ParameterInfo(
              name: p.name?.lexeme ?? '',
              typeSource: typeStr,
              isRequiredPositional: p.isPositional && p.isRequired,
              isRequiredNamed: p.isNamed && p.isRequired,
              isNullable: typeStr.endsWith('?'),
            ));
          }
        }
        methods.add(FunctionInfo(
          name: methodName,
          returnTypeSource: member.returnType?.toString() ?? 'dynamic',
          parameters: params,
          isStatic: member.isStatic,
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
      isChangeNotifier: _ext(superclassName, ['ChangeNotifier', 'ValueNotifier']),
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
    if (node.isGetter || node.isSetter) { super.visitFunctionDeclaration(node); return; }
    final params = <ParameterInfo>[];
    final funcParams = node.functionExpression.parameters?.parameters;
    if (funcParams != null) {
      for (final p in funcParams) {
        final typeStr = p.toString();
        params.add(ParameterInfo(
          name: p.name?.lexeme ?? '',
          typeSource: typeStr,
          isRequiredPositional: p.isPositional && p.isRequired,
          isRequiredNamed: p.isNamed && p.isRequired,
          isNullable: typeStr.endsWith('?'),
        ));
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
    final name = node.constructorName.type.name2.lexeme;
    creationNames.add(name);
    if (const {'MaterialApp', 'Scaffold', 'Text', 'AppBar', 'FloatingActionButton'}.contains(name)) hasMaterial = true;
    if (name == 'CupertinoApp' || name.startsWith('Cupertino')) hasCupertino = true;
    if (const {'ElevatedButton', 'TextButton', 'OutlinedButton', 'FilledButton', 'IconButton', 'FloatingActionButton'}.contains(name)) buttonTypes.add(name);
    if (name == 'TextField' || name == 'TextFormField') { hasTextField = true; textFieldTypes.add(name); }
    if (name == 'Form') hasForm = true;
    if (const {'LinearProgressIndicator', 'CircularProgressIndicator'}.contains(name)) loadingIndicators.add(name);
    if (name == 'FutureBuilder' || name == 'StreamBuilder') hasAsyncBuilder = true;
    if (name == 'Text') {
      for (final argument in node.argumentList.arguments) {
        if (argument is StringLiteral && argument.stringValue != null && argument.stringValue!.isNotEmpty) {
          visibleTexts.add(argument.stringValue!);
          break;
        }
      }
    }
    if (name == 'ValueKey' && node.argumentList.arguments.isNotEmpty) {
      final first = node.argumentList.arguments.first;
      if (first is StringLiteral && first.stringValue != null) keys.add(first.stringValue!);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    if (methodName == 'setState') usesSetState = true;
    if (methodName == 'watch' || methodName == 'read') consumesInheritedState = true;
    super.visitMethodInvocation(node);
  }
}
