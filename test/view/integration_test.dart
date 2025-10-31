// ignore_for_file: prefer_const_constructors

import 'dart:math';

import 'package:horda_server/horda_server.dart';
import 'package:horda_local_host/horda_local_host.dart';
import 'package:test/test.dart';

// Commands
class TestCreateCommand extends RemoteCommand {
  TestCreateCommand();

  factory TestCreateCommand.fromJson(Map<String, dynamic> json) =>
      TestCreateCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestCommand extends RemoteCommand {
  TestCommand(this.val);

  factory TestCommand.fromJson(Map<String, dynamic> json) =>
      TestCommand(json['val']);

  final String val;

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

// Events
class TestCreatedEvent extends RemoteEvent {
  TestCreatedEvent();

  factory TestCreatedEvent.fromJson(Map<String, dynamic> json) =>
      TestCreatedEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestEvent extends RemoteEvent {
  TestEvent(this.val);

  factory TestEvent.fromJson(Map<String, dynamic> json) =>
      TestEvent(json['val']);

  final String val;

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

// Entity
class TestEntity extends Entity<TestEntityState> {
  @override
  String get name => 'TestEntity';

  Future<TestCreatedEvent> handleCreate(
    TestCreateCommand cmd,
    EntityContext ctx,
  ) async {
    return TestCreatedEvent();
  }

  Future<TestEvent> handleCommand(
    TestCommand cmd,
    TestEntityState state,
    EntityContext ctx,
  ) async {
    return TestEvent(cmd.val);
  }

  @override
  void initHandlers(EntityHandlers<TestEntityState> handlers) {
    handlers
      ..addInit<TestCreateCommand, TestCreatedEvent>(
        handleCreate,
        TestCreateCommand.fromJson,
        TestEntityState.fromTestCreated,
      )
      ..add<TestCommand>(
        handleCommand,
        TestCommand.fromJson,
      )
      ..addStateFromJson(TestEntityState.fromJson);
  }

  @override
  void initMigrations(EntityStateMigrations migrations) {
    // noop
  }
}

typedef TestEntityContext = EntityContext;

// State
class TestEntityState implements EntityState {
  TestEntityState();

  TestEntityState.fromTestCreated(TestCreatedEvent event) : this();

  factory TestEntityState.fromJson(Map<String, dynamic> json) {
    return TestEntityState();
  }

  final random = Random();

  @override
  void project(RemoteEvent event) {}

  @override
  Map<String, dynamic> toJson() => {};
}

// ViewGroup
class TestEntityViewGroup implements EntityViewGroup {
  TestEntityViewGroup();

  TestEntityViewGroup.fromTestCreated(TestCreatedEvent event) : this();

  late final view1 = ValueView<String>(
    name: 'view1',
    value: 'value1',
  );

  late final view2 = ValueView<int>(
    name: 'view2',
    value: 0,
  );

  @override
  void initViews(ViewGroup views) {
    views
      ..add(view1)
      ..add(view2);
  }

  @override
  void initProjectors(EntityViewGroupProjectors projectors) {
    projectors
      ..addInit<TestCreatedEvent>(TestEntityViewGroup.fromTestCreated)
      ..add<TestEvent>((event) {
        view1.value = event.val;
        view2.value = 10;
      });
  }
}

void main() {
  test('view should be initialized with default values', () async {
    final system = HordaServerTestSystem();
    final entity = TestEntity();

    system.registerEntity<TestEntityState>(
      entity,
      TestEntityViewGroup(),
    );

    system.start();

    system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());
    system.sendEntity('TestEntity', 'actor2', 'system', TestCreateCommand());

    // Views are initialized via InitViewData directly in ViewStore
    // We just verify entities were created by checking that we can get their view snapshots
    final result1 = await system.viewStore.viewSnapshot(
      'TestEntity',
      'actor1',
      'view1',
    );
    expect(result1.value, 'value1');

    final result2 = await system.viewStore.viewSnapshot(
      'TestEntity',
      'actor1',
      'view2',
    );
    expect(result2.value, 0);

    final result3 = await system.viewStore.viewSnapshot(
      'TestEntity',
      'actor2',
      'view1',
    );
    expect(result3.value, 'value1');

    final result4 = await system.viewStore.viewSnapshot(
      'TestEntity',
      'actor2',
      'view2',
    );
    expect(result4.value, 0);
  });

  test('view should publish change events', () async {
    final system = HordaServerTestSystem();
    final entity = TestEntity();

    system.registerEntity<TestEntityState>(
      entity,
      TestEntityViewGroup(),
    );

    system.start();

    system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());
    system.sendEntity('TestEntity', 'actor2', 'system', TestCreateCommand());

    // Wait for entities to be created
    await Future.delayed(Duration(milliseconds: 10));

    // Verify initial values in ViewStore after entity creation
    final initialView1Actor1 = await system.viewStore.viewSnapshot(
      'TestEntity',
      'actor1',
      'view1',
    );
    expect(initialView1Actor1.value, 'value1');

    final initialView2Actor1 = await system.viewStore.viewSnapshot(
      'TestEntity',
      'actor1',
      'view2',
    );
    expect(initialView2Actor1.value, 0);

    // Subscribe to change streams BEFORE sending commands
    final actor1View1Changes = system.changes(
      entityName: 'TestEntity',
      id: 'actor1',
      name: 'view1',
    );
    final actor1View2Changes = system.changes(
      entityName: 'TestEntity',
      id: 'actor1',
      name: 'view2',
    );
    final actor2View1Changes = system.changes(
      entityName: 'TestEntity',
      id: 'actor2',
      name: 'view1',
    );
    final actor2View2Changes = system.changes(
      entityName: 'TestEntity',
      id: 'actor2',
      name: 'view2',
    );

    // Now send commands that trigger TestEvent
    system.sendEntity('TestEntity', 'actor1', 'test', TestCommand('a1'));
    system.sendEntity('TestEntity', 'actor2', 'test', TestCommand('a2'));

    // Check that change events are published for actor1 view1
    expect(
      actor1View1Changes,
      emitsThrough(
        isA<ChangeEnvelop>().having(
          (e) => e.changes,
          'changes',
          contains(
            isA<ValueViewChanged<String>>().having(
              (c) => c.newValue,
              'newValue',
              'a1',
            ),
          ),
        ),
      ),
    );

    // Check that change events are published for actor1 view2
    expect(
      actor1View2Changes,
      emitsThrough(
        TypeMatcher<ChangeEnvelop>().having(
          (e) => e.changes,
          'changes',
          contains(
            isA<ValueViewChanged<int>>().having(
              (c) => c.newValue,
              'newValue',
              10,
            ),
          ),
        ),
      ),
    );

    // Check that change events are published for actor2 view1
    expect(
      actor2View1Changes,
      emitsThrough(
        TypeMatcher<ChangeEnvelop>().having(
          (e) => e.changes,
          'changes',
          contains(
            isA<ValueViewChanged<String>>().having(
              (c) => c.newValue,
              'newValue',
              'a2',
            ),
          ),
        ),
      ),
    );

    // Check that change events are published for actor2 view2
    expect(
      actor2View2Changes,
      emitsThrough(
        TypeMatcher<ChangeEnvelop>().having(
          (e) => e.changes,
          'changes',
          contains(
            isA<ValueViewChanged<int>>().having(
              (c) => c.newValue,
              'newValue',
              10,
            ),
          ),
        ),
      ),
    );
  });
}
