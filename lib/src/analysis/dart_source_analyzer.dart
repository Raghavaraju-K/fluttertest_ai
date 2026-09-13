import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import '../project/models.dart';

/// AST-based source inspection. Invalid files are returned as skipped by callers.
class DartSourceAnalyzer {
  DartFileInfo analyze(File file) {
    final result = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        throwIfDiagnostics: false);
    final visitor = _SourceVisitor();
    result.unit.accept(visitor);
    return DartFileInfo(
      path: file.path,
      isWidget: visitor.isWidget,
      isLogic: visitor.functions.isNotEmpty ||
          visitor.classes.isNotEmpty && !visitor.isWidget,
      classes: visitor.classes,
      functions: visitor.functions,
      imports: visitor.imports,
      visibleTexts: visitor.visibleTexts,
      hasMaterial: visitor.hasMaterial,
      hasCupertino: visitor.hasCupertino,
    );
  }
}

class _SourceVisitor extends RecursiveAstVisitor<void> {
  final classes = <String>[];
  final functions = <String>[];
  final imports = <String>[];
  final visibleTexts = <String>[];
  bool isWidget = false;
  bool hasMaterial = false;
  bool hasCupertino = false;

  @override
  void visitImportDirective(ImportDirective node) {
    imports.add(node.uri.stringValue ?? '');
    super.visitImportDirective(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    classes.add(node.name.lexeme);
    final parent = node.extendsClause?.superclass.name.lexeme ?? '';
    if (const {
      'Widget',
      'StatelessWidget',
      'StatefulWidget',
      'ConsumerWidget',
      'HookWidget',
      'GetView'
    }.contains(parent)) {
      isWidget = true;
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (!node.isGetter && !node.isSetter) functions.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName.type.name.lexeme;
    if (name == 'MaterialApp' || name == 'Scaffold' || name == 'Text') {
      hasMaterial = true;
    }
    if (name == 'CupertinoApp' || name.startsWith('Cupertino')) {
      hasCupertino = true;
    }
    if (name == 'Text') {
      StringLiteral? literal;
      for (final argument in node.argumentList.arguments) {
        if (argument is StringLiteral) {
          literal = argument;
          break;
        }
      }
      if (literal?.stringValue != null) visibleTexts.add(literal!.stringValue!);
    }
    super.visitInstanceCreationExpression(node);
  }
}
