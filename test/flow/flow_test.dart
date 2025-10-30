// ignore_for_file: prefer_const_constructors

import 'package:horda_local_host/horda_local_host.dart';
import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';
// commands

class TestCreateCommand extends RemoteCommand {
  TestCreateCommand();
  factory TestCreateCommand.fromJson(Map<String, dynamic> json) =>
      TestCreateCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestCommand1 extends RemoteCommand {
  TestCommand1(this.val);

  final String val;

  factory TestCommand1.fromJson(Map<String, dynamic> json) =>
      TestCommand1(json['val']);

  @override
  Map<String, dynamic> toJson() => {'val': val};
}

// events

class TestCreatedEvent extends RemoteEvent {
  TestCreatedEvent();
  factory TestCreatedEvent.fromJson(Map<String, dynamic> json) =>
      TestCreatedEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestEvent1 extends RemoteEvent {
  TestEvent1(this.processId);

  final String processId;

  factory TestEvent1.fromJson(Map<String, dynamic> json) =>
      TestEvent1(json['processId']);

  @override
  Map<String, dynamic> toJson() => {'processId': processId};
}

class TestEvent2 extends RemoteEvent {
  TestEvent2(this.processId);

  final String processId;

  factory TestEvent2.fromJson(Map<String, dynamic> json) =>
      TestEvent2(json['processId']);

  @override
  Map<String, dynamic> toJson() => {'processId': processId};
}

class ResultEvent extends RemoteEvent {
  ResultEvent();
  factory ResultEvent.fromJson(Map<String, dynamic> json) => ResultEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

// entity

class TestEntity extends Entity<TestState> {
  @override
  String get name => 'TestEntity';

  @override
  void initMigrations(EntityStateMigrations migrations) {}

  Future<TestCreatedEvent> initCmd1(
    TestCreateCommand cmd,
    EntityContext context,
  ) async {
    return TestCreatedEvent();
  }

  Future<RemoteEvent> cmd1(
    TestCommand1 cmd,
    TestState state,
    EntityContext context,
  ) async {
    return ResultEvent();
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
      ..addStateFromJson(
          (json) => TestState.fromTestCreated(TestCreatedEvent()));
  }
}

typedef TestEntityContext = EntityContext;

// state

class TestState implements EntityState {
  TestState.fromTestCreated(TestCreatedEvent event);

  @override
  Map<String, dynamic> toJson() => {};

  @override
  void project(RemoteEvent event) {}
}

// process

class TestProcess1 extends Process {
  Future<ProcessResult> handle(TestEvent1 event, ProcessContext context) async {
    context.callEntity(
      name: 'TestEntity',
      id: 'actor1',
      cmd: TestCommand1('ran by ${context.processId}'),
      fac: ResultEvent.fromJson,
    );
    return ProcessResult.ok('handled test event 1');
  }

  @override
  void initHandlers(ProcessHandlers handlers) {
    handlers.add<TestEvent1>(handle, TestEvent1.fromJson);
  }
}

class TestProcess2 extends Process {
  Future<ProcessResult> handle(TestEvent1 event, ProcessContext context) async {
    var res = await context.callEntity<ResultEvent>(
      name: 'TestEntity',
      id: 'actor1',
      cmd: TestCommand1('ran by ${context.processId}'),
      fac: ResultEvent.fromJson,
    );
    expect(res, TypeMatcher<ResultEvent>());
    return ProcessResult.ok();
  }

  @override
  void initHandlers(ProcessHandlers handlers) {
    handlers.add<TestEvent1>(handle, TestEvent1.fromJson);
  }
}

class TestProcess3 extends Process {
  Future<ProcessResult> handle1(
      TestEvent1 event, ProcessContext context) async {
    // Note: Process architecture doesn't have subscribe - processes handle dispatched events
    return ProcessResult.ok();
  }

  Future<ProcessResult> handle2(
      TestEvent2 event, ProcessContext context) async {
    h = event.processId;
    return ProcessResult.ok();
  }

  String? h;

  @override
  void initHandlers(ProcessHandlers handlers) {
    handlers
      ..add<TestEvent1>(handle1, TestEvent1.fromJson)
      ..add<TestEvent2>(handle2, TestEvent2.fromJson);
  }
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
  test('process should init and run on event', () {
    var system = HordaServerTestSystem();
    final entity = TestEntity();

    system.registerEntity<TestState>(
      entity,
      TestViewGroup(),
    );

    system.registerProcess(TestProcess1());

    system.start();

    system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());

    system.dispatchEvent('actor1', TestEvent1('TestProcess1.process1'));
    system.dispatchEvent('actor1', TestEvent1('TestProcess1.process2'));

    expect(
      system.entityCommands('TestEntity', 'actor1'),
      emitsInAnyOrder([
        TypeMatcher<CommandEnvelop>()
            .having((e) => e.type, 'type', 'TestCreateCommand'),
        TypeMatcher<CommandEnvelop>()
            .having((e) => e.type, 'type', 'TestCommand1')
            .having((e) => e.command['val'], 'command.val', 'ran by 1'),
        TypeMatcher<CommandEnvelop>()
            .having((e) => e.type, 'type', 'TestCommand1')
            .having((e) => e.command['val'], 'command.val', 'ran by 2'),
      ]),
    );
  });

  test('process should send command and wait for resulting event', () {
    final system = HordaServerTestSystem();
    final entity = TestEntity();

    system.registerEntity<TestState>(
      entity,
      TestViewGroup(),
    );

    system.registerProcess(TestProcess2());

    system.start();

    system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());

    system.dispatchEvent('actor1', TestEvent1('TestProcess2.process1'));

    expect(
      system.entityCommands('TestEntity', 'actor1'),
      emitsInAnyOrder([
        TypeMatcher<CommandEnvelop>()
            .having((e) => e.type, 'type', 'TestCreateCommand'),
        TypeMatcher<CommandEnvelop>()
            .having((e) => e.type, 'type', 'TestCommand1')
            .having((e) => e.command['val'], 'command.val', 'ran by 1'),
      ]),
    );
  });

  test('process should handle multiple event types', () {
    var process = TestProcess3();
    var system = HordaServerTestSystem();

    system.registerProcess(process);
    system.start();

    system.dispatchEvent('actor1', TestEvent1('actor2'));
    system.dispatchEvent('actor2', TestEvent2('handled'));

    expectDelayed(() => process.h, 'handled');
  });

  test('process should handle dispatched events', () {
    var process = TestProcess3();
    var system = HordaServerTestSystem();

    system.registerProcess(process);
    system.start();

    system.dispatchEvent('actor1', TestEvent2('handled'));

    expectDelayed(() => process.h, 'handled');
  });

  test('process should publish process result after handling an event', () {
    final entity = TestEntity();
    final system = HordaServerTestSystem();

    system.registerEntity<TestState>(
      entity,
      TestViewGroup(),
    );

    system.registerProcess(TestProcess1());

    system.start();

    system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());

    system.dispatchEvent('actor1', TestEvent1('TestProcess1.process1'));

    // Check processResults stream
    expect(
      system.processResults(),
      emits(
        TypeMatcher<ProcessResultEnvelop>().having(
          (e) => e.result.value,
          'value',
          'handled test event 1',
        ),
      ),
    );
  });

  test('dispatching should return a process result', () async {
    final entity = TestEntity();
    final system = HordaServerTestSystem();

    system.registerEntity<TestState>(
      entity,
      TestViewGroup(),
    );

    system.registerProcess(TestProcess1());

    system.start();

    system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());

    // Dispatch event and get result
    final result = await system.dispatchEvent(
      'system',
      TestEvent1('TestProcess1.process1'),
    );

    // Check that system.dispatchEvent returned a proper ProcessResult
    expect(result.value, 'handled test event 1');
    expect(result.isError, false);
  });
}

void expectDelayed<T>(T Function() cb, dynamic matcher) {
  return expect(
    Future<T>.delayed(Duration.zero, cb),
    completion(matcher),
  );
}
