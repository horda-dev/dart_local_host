import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:horda_server/horda_server.dart';
import 'package:source_gen/source_gen.dart';

class HordaTypeChecker {
  HordaTypeChecker._();

  static HordaTypeChecker get instance {
    _instance ??= HordaTypeChecker._();
    return _instance!;
  }

  static HordaTypeChecker? _instance;

  bool isActor(ClassElement element) {
    return _actorChecker.isSuperOf(element);
  }

  bool isState(ClassElement element) {
    return _stateChecker.isAssignableFrom(element);
  }

  bool isViewGroup(ClassElement element) {
    return _viewGroupChecker.isAssignableFrom(element);
  }

  bool isService(ClassElement element) {
    return _serviceChecker.isSuperOf(element);
  }

  bool isProcessGroup(ClassElement element) {
    return _processGroupChecker.isSuperOf(element);
  }

  bool isProcess(MethodElement element) {
    if (!element.isStatic) {
      return false;
    }

    if (element.formalParameters.length != 2) {
      return false;
    }

    final isNotReturningFuture = !element.returnType.isDartAsyncFuture;
    if (isNotReturningFuture) {
      return false;
    }

    final futureTypeArg =
        (element.returnType as ParameterizedType).typeArguments.firstOrNull;
    if (futureTypeArg == null) {
      return false;
    }

    final isNotReturningFlowResult = !_processResultChecker
        .isAssignableFromType(
          futureTypeArg,
        );
    if (isNotReturningFlowResult) {
      return false;
    }

    final [first, second] = element.formalParameters;

    final isNotEvt = !_eventChecker.isAssignableFromType(first.type);
    if (isNotEvt) {
      return false;
    }

    final isNotCtx = !_processContextChecker.isAssignableFromType(second.type);
    if (isNotCtx) {
      return false;
    }

    return true;
  }

  bool isCommand(ClassElement element) {
    return _commandChecker.isAssignableFrom(element);
  }

  bool isEvent(ClassElement element) {
    return _eventChecker.isAssignableFrom(element);
  }

  final _actorChecker = TypeChecker.typeNamed(
    Entity,
    inPackage: 'horda_server',
  );
  final _stateChecker = TypeChecker.typeNamed(
    EntityState,
    inPackage: 'horda_server',
  );
  final _viewGroupChecker = TypeChecker.typeNamed(
    EntityViewGroup,
    inPackage: 'horda_server',
  );
  final _serviceChecker = TypeChecker.typeNamed(
    Service,
    inPackage: 'horda_server',
  );
  final _processGroupChecker = TypeChecker.typeNamed(
    ProcessGroup,
    inPackage: 'horda_server',
  );
  final _processContextChecker = TypeChecker.typeNamed(
    ProcessContext,
    inPackage: 'horda_server',
  );
  final _processResultChecker = TypeChecker.typeNamed(
    ProcessResult,
    inPackage: 'horda_core',
  );
  final _commandChecker = TypeChecker.typeNamed(
    RemoteCommand,
    inPackage: 'horda_core',
  );
  final _eventChecker = TypeChecker.typeNamed(
    RemoteEvent,
    inPackage: 'horda_core',
  );
}
