import 'package:analyzer/dart/element/element.dart';
import 'package:horda_server/horda_server.dart';
import 'package:source_gen/source_gen.dart';

class FluirTypeChecker {
  FluirTypeChecker._();

  static FluirTypeChecker get instance {
    _instance ??= FluirTypeChecker._();
    return _instance!;
  }

  static FluirTypeChecker? _instance;

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

  bool isProcess(ClassElement element) {
    return _processChecker.isSuperOf(element);
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
  final _processChecker = TypeChecker.typeNamed(
    Process,
    inPackage: 'horda_server',
  );
  final _commandChecker = TypeChecker.typeNamed(
    RemoteCommand,
    inPackage: 'horda_server',
  );
  final _eventChecker = TypeChecker.typeNamed(
    RemoteEvent,
    inPackage: 'horda_server',
  );
}
