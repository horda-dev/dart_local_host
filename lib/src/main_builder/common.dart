import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// Get a resolved AST node from an element.
///
/// A resolved node provides the static type and element information.
Future<T> getResolvedNodeFromElement<T extends AstNode>(Element element) async {
  final session = element.session;
  if (session == null) {
    throw GetNodeFromElementException('${element.displayName} has no session');
  }

  final library = element.library;
  if (library == null) {
    throw GetNodeFromElementException('${element.displayName} has no library');
  }

  final resolvedLibary = await session.getResolvedLibraryByElement(library);
  if (resolvedLibary is! ResolvedLibraryResult) {
    throw GetNodeFromElementException(
      '${element.displayName} could not get resolved library',
    );
  }

  final fragmentDeclaration = resolvedLibary.getFragmentDeclaration(
    element.firstFragment,
  );
  if (fragmentDeclaration == null) {
    throw GetNodeFromElementException(
      '${element.displayName} has no declaration',
    );
  }

  final node = fragmentDeclaration.node;
  if (node is! T) {
    throw GetNodeFromElementException(
      'Node of ${element.displayName} element is not $T',
    );
  }

  return node;
}

class GetNodeFromElementException {
  const GetNodeFromElementException(this.message);

  final String message;

  @override
  String toString() => message;
}
