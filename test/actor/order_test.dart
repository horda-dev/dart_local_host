// ignore_for_file: prefer_const_constructors

import 'dart:math';

import 'package:horda_server/horda_server.dart';
import 'package:horda_local_host/horda_local_host.dart';
import 'package:test/test.dart';

abstract class TestActorCommand extends RemoteCommand {
  @override
  Map<String, dynamic> toJson();
}

class TestCreateCommand extends TestActorCommand {
  TestCreateCommand();
  factory TestCreateCommand.fromJson(Map<String, dynamic> json) =>
      TestCreateCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestCommand extends TestActorCommand {
  TestCommand(this.val);

  final int val;

  factory TestCommand.fromJson(Map<String, dynamic> json) =>
      TestCommand(json['val']);

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

// events

abstract class TestActorEvent extends RemoteEvent {
  @override
  Map<String, dynamic> toJson();
}

class TestCreatedEvent extends TestActorEvent {
  TestCreatedEvent();
  factory TestCreatedEvent.fromJson(Map<String, dynamic> json) =>
      TestCreatedEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestEvent extends TestActorEvent {
  TestEvent(this.val);

  final int val;

  factory TestEvent.fromJson(Map<String, dynamic> json) =>
      TestEvent(json['val']);

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

// actor

class TestActor extends Entity<TestState> {
  @override
  void initMigrations(EntityStateMigrations migrations) {}

  Future<TestCreatedEvent> initCmd1(
    TestCreateCommand cmd,
    EntityContext context,
  ) async {
    return TestCreatedEvent();
  }

  Future<TestActorEvent> cmd1(
    TestCommand cmd,
    TestState state,
    EntityContext context,
  ) async {
    int delay = state.random.nextInt(100);

    return Future.delayed(
      Duration(milliseconds: delay),
      () => TestEvent(cmd.val),
    );
  }

  @override
  void initHandlers(EntityHandlers<TestState> handlers) {
    handlers
      ..addInit<TestCreateCommand, TestCreatedEvent>(
        initCmd1,
        TestCreateCommand.fromJson,
        TestState.fromTestCreated,
      )
      ..add<TestCommand>(cmd1, TestCommand.fromJson);
  }
}

typedef TestActorContext = EntityContext;

// state

class TestState implements EntityState {
  TestState.fromTestCreated(TestCreatedEvent event);

  final random = Random();

  @override
  Map<String, dynamic> toJson() => {};

  @override
  void project(RemoteEvent event) {}
}

// view group
class TestViewGroup implements EntityViewGroup {
  TestViewGroup();

  TestViewGroup.fromTestCreated(TestCreatedEvent event);

  @override
  void initViews(ViewGroup views) {}

  @override
  void initProjectors(EntityViewGroupProjectors projectors) {
    projectors.addInit<TestCreatedEvent>(TestViewGroup.fromTestCreated);
  }
}

void main() {
  test('actor should process commands in order received', () async {
    final system = HordaServerTestSystem();
    final actor = TestActor();

    system.registerEntity<TestState>(
      actor,
      TestViewGroup(),
    );

    system.start();

    system.sendEntity(actor.name, 'actor1', 'system', TestCreateCommand());
    system.sendEntity(actor.name, 'actor2', 'system', TestCreateCommand());

    for (var command in List.generate(10, (i) => TestCommand(i + 1))) {
      system.sendEntity(actor.name, 'actor1', 'test', command);
      system.sendEntity(actor.name, 'actor2', 'test', command);
    }

    expect(
      system.entityEvents(entityId: 'actor1'),
      emitsInOrder([
        TypeMatcher<EventEnvelop>()
            .having((e) => e.type, 'type', 'TestCreatedEvent')
            .having((e) => e.event, 'event', <String, dynamic>{}),
        ...List.generate(
          10,
          (i) => TypeMatcher<EventEnvelop>()
              .having((e) => e.type, 'type', 'TestEvent')
              .having((e) => e.event, 'event', <String, dynamic>{'val': i + 1}),
        ),
      ]),
    );

    expect(
      system.entityEvents(entityId: 'actor2'),
      emitsInOrder([
        TypeMatcher<EventEnvelop>()
            .having((e) => e.type, 'type', 'TestCreatedEvent')
            .having((e) => e.event, 'event', <String, dynamic>{}),
        ...List.generate(
          10,
          (i) => TypeMatcher<EventEnvelop>()
              .having((e) => e.type, 'type', 'TestEvent')
              .having((e) => e.event, 'event', <String, dynamic>{'val': i + 1}),
        ),
      ]),
    );
  });
}
