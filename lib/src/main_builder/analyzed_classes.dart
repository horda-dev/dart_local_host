import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'common.dart';

class AnalyzedClass {
  AnalyzedClass(this.element);

  final ClassElement element;

  String get name {
    return element.name ?? 'NO-NAME';
  }
}

class AnalyzedActor extends AnalyzedClass {
  AnalyzedActor(super.element);

  late AnalyzedState state;
  late AnalyzedViewGroup viewGroup;

  void linkState(AnalyzedState state) {
    this.state = state;
  }

  void linkViewGroup(AnalyzedViewGroup viewGroup) {
    this.viewGroup = viewGroup;
  }
}

class AnalyzedState extends AnalyzedClass {
  AnalyzedState(super.element);
}

class AnalyzedViewGroup extends AnalyzedClass {
  AnalyzedViewGroup(super.element);
}

class AnalyzedService extends AnalyzedClass {
  AnalyzedService(super.element);
}

class AnalyzedProcessGroup extends AnalyzedClass {
  AnalyzedProcessGroup(super.element);

  final Set<String> eventTypes = {};

  Future<void> extractEventTypes() async {
    // Find the registerFuncs method
    final registerFuncsMethod = element.methods
        .where((m) => m.name == 'registerFuncs')
        .firstOrNull;

    if (registerFuncsMethod == null) {
      return;
    }

    try {
      // Get resolved AST node to traverse method body
      final node = await getResolvedNodeFromElement<MethodDeclaration>(
        registerFuncsMethod,
      );

      // Use visitor to extract event types from funcs.add<T>() calls
      final visitor = _RegisterFuncsVisitor();
      node.body.accept(visitor);

      eventTypes.addAll(visitor.eventTypes);
    } catch (e) {
      // If we can't parse the method, just continue without event types
      // This is non-critical for the builder
    }
  }
}

/// Visitor to extract event type names from funcs.add<T>() method calls
class _RegisterFuncsVisitor extends RecursiveAstVisitor<void> {
  final eventTypes = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Check if this is a funcs.add<T>() call
    if (node.methodName.name == 'add' &&
        node.typeArguments != null &&
        node.typeArguments!.arguments.isNotEmpty) {
      // Extract T from <T>
      final typeArg = node.typeArguments!.arguments.first;
      final eventName = typeArg.toString();

      eventTypes.add(eventName);
    }

    super.visitMethodInvocation(node);
  }
}

class AnalyzedCommand extends AnalyzedClass {
  AnalyzedCommand(super.element);
}

class AnalyzedEvent extends AnalyzedClass {
  AnalyzedEvent(super.element);
}
