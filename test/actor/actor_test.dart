// ignore_for_file: prefer_const_constructors

import 'package:horda_local_host/src/system.dart';
import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

// commands

abstract class TestActorCommand extends RemoteCommand {
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError();
  }
}

class TestCreateCommand extends TestActorCommand {
  TestCreateCommand(this.val);

  final int val;

  factory TestCreateCommand.fromJson(Map<String, dynamic> json) =>
      TestCreateCommand(json['val']);

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

class TestCommand1 extends TestActorCommand {
  TestCommand1();
  factory TestCommand1.fromJson(Map<String, dynamic> json) => TestCommand1();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestCommand2 extends TestActorCommand {
  TestCommand2();
  factory TestCommand2.fromJson(Map<String, dynamic> json) => TestCommand2();

  @override
  Map<String, dynamic> toJson() => {};
}

class WrongCommand extends RemoteCommand {
  WrongCommand();
  @override
  Map<String, dynamic> toJson() => {};

  factory WrongCommand.fromJson(Map<String, dynamic> json) => WrongCommand();
}

// events

abstract class TestActorEvent extends RemoteEvent {
  @override
  Map<String, dynamic> toJson();
}

class TestCreatedEvent extends TestActorEvent {
  TestCreatedEvent(this.val);

  final int val;

  factory TestCreatedEvent.fromJson(Map<String, dynamic> json) =>
      TestCreatedEvent(json['val']);

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

class TestEvent1 extends TestActorEvent {
  TestEvent1(this.val);

  final String val;

  factory TestEvent1.fromJson(Map<String, dynamic> json) =>
      TestEvent1(json['val']);

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

class TestEvent2 extends TestActorEvent {
  TestEvent2(this.val);

  final String val;

  factory TestEvent2.fromJson(Map<String, dynamic> json) =>
      TestEvent2(json['val']);

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
    return TestCreatedEvent(cmd.val);
  }

  Future<TestActorEvent> cmd1(
    TestCommand1 cmd,
    TestState state,
    EntityContext context,
  ) async {
    return TestEvent1('${state.val}-cmd1');
  }

  Future<TestActorEvent> cmd2(
    TestCommand2 cmd,
    TestState state,
    EntityContext context,
  ) async {
    return TestEvent2('${state.val}-cmd2');
  }

  @override
  void initHandlers(EntityHandlers<TestState> handlers) {
    handlers
      ..addInit<TestCreateCommand, TestCreatedEvent>(
        initCmd1,
        TestCreateCommand.fromJson,
        TestState.fromTestCreated,
      )
      ..add<TestCommand1>(cmd1, TestCommand1.fromJson)
      ..add<TestCommand2>(cmd2, TestCommand2.fromJson);
  }
}

typedef TestActorContext = EntityContext;

// state

class TestState implements EntityState {
  TestState(this.val);

  TestState.fromTestCreated(TestCreatedEvent event) {
    val = event.val;
  }

  var val = 0;

  void event1(TestEvent1 event) {
    val += 1;
  }

  void event2(TestEvent2 event) {
    val += 1;
  }

  @override
  Map<String, dynamic> toJson() => {'val': val};

  @override
  void project(RemoteEvent event) {
    if (event is TestEvent1) {
      event1(event);
    } else if (event is TestEvent2) {
      event2(event);
    }
  }
}

class TestViewGroup implements EntityViewGroup {
  TestViewGroup() : val = ValueView<int>(name: 'val', value: 0);

  TestViewGroup.fromTestCreated(TestCreatedEvent event)
      : val = ValueView(name: 'val', value: event.val);

  late final ValueView<int> val;

  @override
  void initViews(ViewGroup views) {
    views.add(val);
  }

  @override
  void initProjectors(EntityViewGroupProjectors projectors) {
    projectors.addInit<TestCreatedEvent>(TestViewGroup.fromTestCreated);
  }
}

void main() {
  test('actor should handle commands and project events', () {
    var system = HordaServerTestSystem();

    final actor = TestActor();

    system.registerEntity<TestState>(
      actor,
      TestViewGroup(),
    );

    system.start();

    // Start actors via start command
    system.sendEntity(actor.name, 'actor1', 'system', TestCreateCommand(10));
    system.sendEntity(actor.name, 'actor2', 'system', TestCreateCommand(20));

    // Test command handling and event projection
    system.sendEntity(actor.name, 'actor1', 'system', TestCommand1());
    system.sendEntity(actor.name, 'actor2', 'system', TestCommand1());

    system.sendEntity(actor.name, 'actor1', 'system', TestCommand2());
    system.sendEntity(actor.name, 'actor2', 'system', TestCommand2());

    expect(
      system.entityEvents(entityId: 'actor1').map((e) => e.event),
      emitsInOrder([
        <String, dynamic>{'val': 10},
        <String, dynamic>{'val': '10-cmd1'},
        <String, dynamic>{'val': '11-cmd2'},
      ]),
    );

    expect(
      system.entityEvents(entityId: 'actor2').map((e) => e.event),
      emitsInOrder([
        <String, dynamic>{'val': 20},
        <String, dynamic>{'val': '20-cmd1'},
        <String, dynamic>{'val': '21-cmd2'},
      ]),
    );
  });

  test('actor should publish correct event envelops', () {
    final system = HordaServerTestSystem();

    final actor = TestActor();

    system.registerEntity<TestState>(
      actor,
      TestViewGroup(),
    );

    system.start();

    system.sendEntity(actor.name, 'actor1', 'system', TestCreateCommand(10));
    system.sendEntity(actor.name, 'actor1', 'test', TestCommand1());

    expect(
      system.entityEvents(entityId: 'actor1'),
      emitsInOrder(
        [
          // TestCreatedEvent
          TypeMatcher<EventEnvelop>()
              .having((e) => e.actorId, 'actorId', 'actor1')
              .having((e) => e.commandId, 'commandId', '1'),
          // TestEvent1
          TypeMatcher<EventEnvelop>()
              .having((e) => e.actorId, 'actorId', 'actor1')
              .having((e) => e.commandId, 'commandId', '2'),
        ],
      ),
    );
  });

  test('actor should ignore commands it cannot handle', () {
    var system = HordaServerTestSystem();

    final actor = TestActor();

    system.registerEntity<TestState>(
      actor,
      TestViewGroup(),
    );

    system.start();

    system.sendEntity(actor.name, 'actor1', 'system', TestCreateCommand(0));
    system.sendEntity(actor.name, 'actor1', 'system', WrongCommand());

    expect(
      system.entityEvents(entityId: 'actor1').map((e) => e.event),
      emitsInOrder([]),
    );
  });
}
