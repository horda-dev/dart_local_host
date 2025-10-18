// ignore_for_file: prefer_const_constructors

import 'package:horda_local_host/horda_local_host.dart';
import 'package:horda_local_host/src/system.dart';
import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

// Commands

class IncrementCommand extends RemoteCommand {
  IncrementCommand();
  factory IncrementCommand.fromJson(Map<String, dynamic> json) =>
      IncrementCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

// Events

class IncrementedEvent extends RemoteEvent {
  IncrementedEvent(this.newCount);

  final int newCount;

  factory IncrementedEvent.fromJson(Map<String, dynamic> json) =>
      IncrementedEvent(json['newCount']);

  @override
  Map<String, dynamic> toJson() => {'newCount': newCount};
}

// State

class SingletonState implements EntityState {
  SingletonState({this.count = 0});

  int count;

  void increment() {
    count += 1;
  }

  @override
  Map<String, dynamic> toJson() => {'count': count};

  @override
  void project(RemoteEvent event) {
    if (event is IncrementedEvent) {
      increment();
    }
  }
}

// Entity - Singleton

class SingletonEntity extends Entity<SingletonState> {
  @override
  SingletonState? get singleton => SingletonState(count: 42);

  @override
  void initMigrations(EntityStateMigrations migrations) {}

  Future<IncrementedEvent> handleIncrement(
    IncrementCommand cmd,
    SingletonState state,
    EntityContext context,
  ) async {
    // State will be incremented after this event is projected
    return IncrementedEvent(state.count + 1);
  }

  @override
  void initHandlers(EntityHandlers<SingletonState> handlers) {
    handlers.add<IncrementCommand>(
      handleIncrement,
      IncrementCommand.fromJson,
    );
  }
}

// ViewGroup

class SingletonViewGroup implements EntityViewGroup {
  SingletonViewGroup() : count = ValueView<int>(name: 'count', value: 10);

  late final ValueView<int> count;

  @override
  void initViews(ViewGroup views) {
    views.add(count);
  }

  @override
  void initProjectors(EntityViewGroupProjectors projectors) {
    // Singleton entities don't need init projectors
    // Views use default values
  }
}

void main() {
  test('singleton entity should initialize without init command', () async {
    var system = HordaServerTestSystem();

    final entity = SingletonEntity();

    system.registerEntity<SingletonState>(
      entity,
      SingletonViewGroup(),
    );

    await system.start();

    // Singleton is pre-created at registration with ID = kSingletonId
    // Send a regular command directly (no init command needed)
    system.sendEntity(entity.name, kSingletonId, 'system', IncrementCommand());

    // Verify the entity processed the command
    expect(
      system.entityEvents(entityId: kSingletonId).map((e) => e.type),
      emitsInOrder([
        'IncrementedEvent',
      ]),
    );
  });

  test('singleton entity should have initial state from singleton getter',
      () async {
    var system = HordaServerTestSystem();

    final entity = SingletonEntity();

    system.registerEntity<SingletonState>(
      entity,
      SingletonViewGroup(),
    );

    await system.start();

    // Send two commands to verify state persists correctly
    // Singleton uses kSingletonId as ID
    system.sendEntity(entity.name, kSingletonId, 'system', IncrementCommand());
    system.sendEntity(entity.name, kSingletonId, 'system', IncrementCommand());

    // State starts at 42 (from singleton) and increments to 43, then 44
    expect(
      system.entityEvents(entityId: kSingletonId).map((e) => e.event),
      emitsInOrder([
        {'newCount': 43}, // First increment: 42 + 1 = 43
        {'newCount': 44}, // Second increment: 43 + 1 = 44
      ]),
    );
  });

  test('singleton entity rejects commands with wrong ID', () async {
    var system = HordaServerTestSystem();

    final entity = SingletonEntity();

    system.registerEntity<SingletonState>(
      entity,
      SingletonViewGroup(),
    );

    await system.start();

    // Attempting to use a different ID should throw an error
    expect(
      () => system.sendEntity(
        entity.name,
        'wrong-id', // ← Wrong ID! Should be kSingletonId
        'system',
        IncrementCommand(),
      ),
      throwsA(
        isA<HordaLocalHostError>().having(
          (e) => e.message,
          'message',
          contains('Singleton entity ${entity.name} must be addressed by the constant ID "$kSingletonId"'),
        ),
      ),
    );
  });

  test('singleton entity is pre-created at registration', () async {
    var system = HordaServerTestSystem();

    final entity = SingletonEntity();

    system.registerEntity<SingletonState>(
      entity,
      SingletonViewGroup(),
    );

    await system.start();

    // Singleton is pre-created, so we can send commands immediately
    system.sendEntity(entity.name, kSingletonId, 'system', IncrementCommand());

    // Wait for command to be processed
    await system.entityEvents(entityId: kSingletonId).first;

    // Query the view to verify it exists
    final queryBuilder = QueryDefBuilder(entity.name)..val('count');

    final result = await system.viewStore.query(
      actorId: kSingletonId,
      name: '',
      query: queryBuilder.build(),
    );

    // View should exist and retain default value (10) since no projectors update it
    // Note: Entity state is 43 after increment, but view stays at default
    expect(result.views['count'], isA<ValueQueryResult>());
    final countView = result.views['count'] as ValueQueryResult;
    expect(countView.value, equals(10));
  });

  test('singleton view can be queried without sending commands', () async {
    var system = HordaServerTestSystem();

    final entity = SingletonEntity();

    system.registerEntity<SingletonState>(
      entity,
      SingletonViewGroup(),
    );

    await system.start();

    // Query the view immediately without sending any commands
    final queryBuilder = QueryDefBuilder(entity.name)..val('count');

    final result = await system.viewStore.query(
      actorId: kSingletonId,
      name: '',
      query: queryBuilder.build(),
    );

    // View should be initialized with default value (10)
    // Note: State has count=42, but view has its own default value
    expect(result.views['count'], isA<ValueQueryResult>());
    final countView = result.views['count'] as ValueQueryResult;
    expect(countView.value, equals(10));
  });

  test('singleton entity cannot add init handlers', () async {
    // Create an entity that tries to add init handlers
    final entity = InvalidSingletonEntityWithInitHandler();

    expect(
      () => HordaServerTestSystem().registerEntity<SingletonState>(
        entity,
        SingletonViewGroup(),
      ),
      throwsA(
        isA<HordaLocalHostError>().having(
          (e) => e.message,
          'message',
          contains('Singleton entity ${entity.name} cannot add init handlers'),
        ),
      ),
    );
  });

  test('singleton entity cannot add init projectors', () async {
    // Create an entity that tries to add init projectors
    final entity = InvalidSingletonEntityWithInitProjector();

    expect(
      () => HordaServerTestSystem().registerEntity<SingletonState>(
        entity,
        InvalidSingletonViewGroupWithInitProjector(),
      ),
      throwsA(
        isA<HordaLocalHostError>().having(
          (e) => e.message,
          'message',
          contains(
              'Singleton entity view group for ${entity.name} cannot add init projectors'),
        ),
      ),
    );
  });
}

// Invalid singleton entity that attempts to add init handler
class InvalidSingletonEntityWithInitHandler extends Entity<SingletonState> {
  @override
  SingletonState? get singleton => SingletonState(count: 42);

  @override
  void initMigrations(EntityStateMigrations migrations) {}

  @override
  void initHandlers(EntityHandlers<SingletonState> handlers) {
    // This should throw because it's a singleton
    handlers.addInit<IncrementCommand, IncrementedEvent>(
      (cmd, context) async => IncrementedEvent(1),
      IncrementCommand.fromJson,
      (event) => SingletonState(count: 0),
    );
  }
}

// Invalid singleton entity with init projector
class InvalidSingletonEntityWithInitProjector extends Entity<SingletonState> {
  @override
  SingletonState? get singleton => SingletonState(count: 42);

  @override
  void initMigrations(EntityStateMigrations migrations) {}

  @override
  void initHandlers(EntityHandlers<SingletonState> handlers) {
    // No init handler, that's fine
  }
}

// Invalid view group that attempts to add init projector
class InvalidSingletonViewGroupWithInitProjector implements EntityViewGroup {
  InvalidSingletonViewGroupWithInitProjector()
      : count = ValueView<int>(name: 'count', value: 10);

  late final ValueView<int> count;

  @override
  void initViews(ViewGroup views) {
    views.add(count);
  }

  @override
  void initProjectors(EntityViewGroupProjectors projectors) {
    // This should throw because it's a singleton
    projectors.addInit<IncrementedEvent>(
      (event) => SingletonViewGroup(),
    );
  }
}
