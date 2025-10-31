import 'package:analyzer/dart/element/element.dart';
import 'package:source_gen/source_gen.dart';

import 'analyzed_classes.dart';
import 'type_checker.dart';

class AnalyzedPackage {
  AnalyzedPackage();

  final actors = <String, AnalyzedActor>{};
  final states = <String, AnalyzedState>{};
  final viewGroups = <String, AnalyzedViewGroup>{};
  final services = <String, AnalyzedService>{};
  final processGroups = <String, AnalyzedProcessGroup>{};
  final commands = <String, AnalyzedCommand>{};
  final events = <String, AnalyzedEvent>{};

  void read(LibraryReader reader) {
    for (final c in reader.classes) {
      if (_typeChecker.isActor(c)) {
        _analyzeActor(c);
        continue;
      }

      if (_typeChecker.isState(c)) {
        _analyzeState(c);
        continue;
      }

      if (_typeChecker.isViewGroup(c)) {
        _analyzeViewGroup(c);
        continue;
      }

      if (_typeChecker.isService(c)) {
        _analyzeService(c);
        continue;
      }

      if (_typeChecker.isProcessGroup(c)) {
        _analyzeProcessGroup(c);
        continue;
      }

      if (_typeChecker.isCommand(c)) {
        _analyzeCommand(c);
        continue;
      }

      if (_typeChecker.isEvent(c)) {
        _analyzeEvent(c);
        continue;
      }
    }
  }

  void linkStatesAndViewGroupsToActors() {
    for (final e in actors.entries) {
      final name = e.key;
      final actor = e.value;

      actor.linkState(
        _findStateForActor(name),
      );

      actor.linkViewGroup(
        _findViewGroupForActor(name),
      );
    }
  }

  void _analyzeActor(ClassElement element) {
    final actor = AnalyzedActor(element);

    if (actors.containsKey(actor.name)) {
      print('Skipped duplicate actor: ${actor.name}');
      return;
    }

    actors[actor.name] = actor;
  }

  void _analyzeState(ClassElement element) {
    final state = AnalyzedState(element);

    if (states.containsKey(state.name)) {
      print('Skipped duplicate state: ${state.name}');
      return;
    }

    states[state.name] = state;
  }

  void _analyzeViewGroup(ClassElement element) {
    final viewgroup = AnalyzedViewGroup(element);

    if (viewGroups.containsKey(viewgroup.name)) {
      print('Skipped duplicate viewgroup: ${viewgroup.name}');
      return;
    }

    viewGroups[viewgroup.name] = viewgroup;
  }

  void _analyzeService(ClassElement element) {
    final service = AnalyzedService(element);

    if (services.containsKey(service.name)) {
      print('Skipped duplicate service: ${service.name}');
      return;
    }

    services[service.name] = service;
  }

  void _analyzeProcessGroup(ClassElement element) {
    final processGroup = AnalyzedProcessGroup(element);

    if (processGroups.containsKey(processGroup.name)) {
      print('Skipped duplicate process group: ${processGroup.name}');
      return;
    }

    processGroups[processGroup.name] = processGroup;
  }

  void _analyzeCommand(ClassElement element) {
    final command = AnalyzedCommand(element);

    if (commands.containsKey(command.name)) {
      print('Skipped duplicate command: ${command.name}');
      return;
    }

    commands[command.name] = command;
  }

  void _analyzeEvent(ClassElement element) {
    final event = AnalyzedEvent(element);

    if (events.containsKey(event.name)) {
      print('Skipped duplicate event: ${event.name}');
      return;
    }

    events[event.name] = event;
  }

  /// State classes usually follow the naming pattern "SomeEntityState", where "SomeEntity" is the name of actor class.
  ///
  /// Since Delurk server doesn't follow this convetion completely, "SomeState" pattern is also expected as a fallback.
  AnalyzedState _findStateForActor(String actorName) {
    var baseActorName = actorName;

    if (actorName.endsWith('Entity')) {
      baseActorName = actorName.substring(
        0,
        actorName.length - 'Entity'.length,
      );
    }

    var state = states['${baseActorName}EntityState'];
    if (state != null) {
      return state;
    }

    state = states['${baseActorName}State'];
    if (state != null) {
      return state;
    }

    print('Failed to find state for $actorName');

    throw Exception(
      'Failed to find state for $actorName.'
      '\nWhen creating an entity make sure to create a state.'
      '\nThe state\'s class name must follow the pattern [ENTITY_NAME]EntityState.'
      '\nE.g.: UserEntity -> UserEntityState, ProductEntity -> ProductEntityState.',
    );
  }

  /// ViewGroup classes follow the naming pattern "SomeViewGroup", where word "Entity" is omitted.
  AnalyzedViewGroup _findViewGroupForActor(String actorName) {
    var prefix = actorName;

    if (actorName.endsWith('Entity')) {
      prefix = actorName.substring(0, actorName.length - 'Entity'.length);
    }

    try {
      return viewGroups.values.firstWhere(
        (vg) => vg.name == '${prefix}ViewGroup',
      );
    } on StateError catch (e, _) {
      // print('Failed to find viewgroup for $actorName, prefix $prefix: $e');
      // print('Stack:\n$s');
      throw Exception(
        'Failed to find view group for $actorName.'
        '\nWhen creating an entity make sure to create a view group.'
        '\nThe view group\'s class name must follow the pattern [ENTITY_NAME]ViewGroup'
        '\nE.g.: UserEntity -> UserViewGroup, ProductEntity -> ProductViewGroup.',
      );
    }
  }

  final _typeChecker = FluirTypeChecker.instance;
}
