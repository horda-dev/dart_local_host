// ignore_for_file: prefer_const_constructors

import 'package:horda_local_host/horda_local_host.dart';
import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

// ============================================================================
// Commands
// ============================================================================

class TestCreateCommand extends RemoteCommand {
  TestCreateCommand();
  factory TestCreateCommand.fromJson(Map<String, dynamic> json) =>
      TestCreateCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

class ThrowCommand extends RemoteCommand {
  ThrowCommand();
  factory ThrowCommand.fromJson(Map<String, dynamic> json) => ThrowCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

class WrongTypeCommand extends RemoteCommand {
  WrongTypeCommand();
  factory WrongTypeCommand.fromJson(Map<String, dynamic> json) =>
      WrongTypeCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

// ============================================================================
// Events
// ============================================================================

class TestCreatedEvent extends RemoteEvent {
  TestCreatedEvent();
  factory TestCreatedEvent.fromJson(Map<String, dynamic> json) =>
      TestCreatedEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class EmptyEvent extends RemoteEvent {
  EmptyEvent();
  factory EmptyEvent.fromJson(Map<String, dynamic> json) => EmptyEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class AlternativeEvent extends RemoteEvent {
  AlternativeEvent();
  factory AlternativeEvent.fromJson(Map<String, dynamic> json) =>
      AlternativeEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TriggerEntityThrowEvent extends RemoteEvent {
  TriggerEntityThrowEvent();
  factory TriggerEntityThrowEvent.fromJson(Map<String, dynamic> json) =>
      TriggerEntityThrowEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TriggerEntityWrongTypeEvent extends RemoteEvent {
  TriggerEntityWrongTypeEvent();
  factory TriggerEntityWrongTypeEvent.fromJson(Map<String, dynamic> json) =>
      TriggerEntityWrongTypeEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TriggerServiceThrowEvent extends RemoteEvent {
  TriggerServiceThrowEvent();
  factory TriggerServiceThrowEvent.fromJson(Map<String, dynamic> json) =>
      TriggerServiceThrowEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TriggerServiceWrongTypeEvent extends RemoteEvent {
  TriggerServiceWrongTypeEvent();
  factory TriggerServiceWrongTypeEvent.fromJson(Map<String, dynamic> json) =>
      TriggerServiceWrongTypeEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TriggerEntityDynamicWrongTypeEvent extends RemoteEvent {
  TriggerEntityDynamicWrongTypeEvent();
  factory TriggerEntityDynamicWrongTypeEvent.fromJson(
    Map<String, dynamic> json,
  ) => TriggerEntityDynamicWrongTypeEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TriggerServiceDynamicWrongTypeEvent extends RemoteEvent {
  TriggerServiceDynamicWrongTypeEvent();
  factory TriggerServiceDynamicWrongTypeEvent.fromJson(
    Map<String, dynamic> json,
  ) => TriggerServiceDynamicWrongTypeEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TriggerProcessUnhandledExceptionEvent extends RemoteEvent {
  TriggerProcessUnhandledExceptionEvent();
  factory TriggerProcessUnhandledExceptionEvent.fromJson(
    Map<String, dynamic> json,
  ) => TriggerProcessUnhandledExceptionEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

// ============================================================================
// Entity
// ============================================================================

class TestEntity extends Entity<TestEntityState> {
  @override
  String get name => 'TestEntity';

  @override
  void initMigrations(EntityStateMigrations migrations) {}

  Future<TestCreatedEvent> initCmd(
    TestCreateCommand cmd,
    EntityContext context,
  ) async {
    return TestCreatedEvent();
  }

  Future<EmptyEvent> throwHandler(
    ThrowCommand cmd,
    TestEntityState state,
    EntityContext context,
  ) async {
    throw Exception('Entity handler intentionally threw an error');
  }

  Future<AlternativeEvent> wrongTypeHandler(
    WrongTypeCommand cmd,
    TestEntityState state,
    EntityContext context,
  ) async {
    return AlternativeEvent();
  }

  @override
  void initHandlers(EntityHandlers<TestEntityState> handlers) {
    handlers
      ..addInit<TestCreateCommand, TestCreatedEvent>(
        initCmd,
        TestCreateCommand.fromJson,
        TestEntityState.fromTestCreated,
      )
      ..add<ThrowCommand>(throwHandler, ThrowCommand.fromJson)
      ..add<WrongTypeCommand>(wrongTypeHandler, WrongTypeCommand.fromJson)
      ..addStateFromJson(
        (json) => TestEntityState.fromTestCreated(TestCreatedEvent()),
      );
  }
}

class TestEntityState implements EntityState {
  TestEntityState.fromTestCreated(TestCreatedEvent event);

  @override
  Map<String, dynamic> toJson() => {};

  @override
  void project(RemoteEvent event) {}
}

class TestEntityViewGroup implements EntityViewGroup {
  TestEntityViewGroup();
  TestEntityViewGroup.fromTestCreated(TestCreatedEvent event);

  @override
  void initViews(ViewGroup views) {}

  @override
  void initProjectors(EntityViewGroupProjectors projectors) {
    projectors.addInit<TestCreatedEvent>(
      TestEntityViewGroup.fromTestCreated,
    );
  }
}

// ============================================================================
// Service
// ============================================================================

class TestService extends Service {
  @override
  String get name => 'TestService';

  Future<EmptyEvent> throwHandler(
    ThrowCommand cmd,
    ServiceContext context,
  ) async {
    throw Exception('Service handler intentionally threw an error');
  }

  Future<AlternativeEvent> wrongTypeHandler(
    WrongTypeCommand cmd,
    ServiceContext context,
  ) async {
    return AlternativeEvent();
  }

  @override
  void initHandlers(ServiceHandlers handlers) {
    handlers
      ..add<ThrowCommand>(throwHandler, ThrowCommand.fromJson)
      ..add<WrongTypeCommand>(wrongTypeHandler, WrongTypeCommand.fromJson);
  }
}

// ============================================================================
// Process Group
// ============================================================================

class TestProcessGroup extends ProcessGroup {
  Error? entityThrowError;
  Error? entityWrongTypeError;
  Error? entityDynamicWrongTypeError;
  Error? serviceThrowError;
  Error? serviceWrongTypeError;
  Error? serviceDynamicWrongTypeError;

  Future<ProcessResult> handleEntityThrow(
    TriggerEntityThrowEvent event,
    ProcessContext context,
  ) async {
    try {
      await context.callEntity<EmptyEvent>(
        name: 'TestEntity',
        id: 'test1',
        cmd: ThrowCommand(),
        fac: EmptyEvent.fromJson,
      );
      return ProcessResult.error('Expected callEntity to throw but it did not');
    } catch (e) {
      entityThrowError = e as Error;
      return ProcessResult.ok('Caught error as expected');
    }
  }

  Future<ProcessResult> handleEntityWrongType(
    TriggerEntityWrongTypeEvent event,
    ProcessContext context,
  ) async {
    try {
      await context.callEntity<EmptyEvent>(
        name: 'TestEntity',
        id: 'test1',
        cmd: WrongTypeCommand(),
        fac: EmptyEvent.fromJson,
      );
      return ProcessResult.error(
        'Expected callEntity to throw due to type mismatch but it did not',
      );
    } catch (e) {
      entityWrongTypeError = e as Error;
      return ProcessResult.ok('Caught type mismatch error as expected');
    }
  }

  Future<ProcessResult> handleServiceThrow(
    TriggerServiceThrowEvent event,
    ProcessContext context,
  ) async {
    try {
      await context.callService<EmptyEvent>(
        name: 'TestService',
        cmd: ThrowCommand(),
        fac: EmptyEvent.fromJson,
      );
      return ProcessResult.error(
        'Expected callService to throw but it did not',
      );
    } catch (e) {
      serviceThrowError = e as Error;
      return ProcessResult.ok('Caught error as expected');
    }
  }

  Future<ProcessResult> handleServiceWrongType(
    TriggerServiceWrongTypeEvent event,
    ProcessContext context,
  ) async {
    try {
      await context.callService<EmptyEvent>(
        name: 'TestService',
        cmd: WrongTypeCommand(),
        fac: EmptyEvent.fromJson,
      );
      return ProcessResult.error(
        'Expected callService to throw due to type mismatch but it did not',
      );
    } catch (e) {
      serviceWrongTypeError = e as Error;
      return ProcessResult.ok('Caught type mismatch error as expected');
    }
  }

  Future<ProcessResult> handleEntityDynamicWrongType(
    TriggerEntityDynamicWrongTypeEvent event,
    ProcessContext context,
  ) async {
    try {
      await context.callEntityDynamic(
        name: 'TestEntity',
        id: 'test1',
        cmd: WrongTypeCommand(),
        fac: [EmptyEvent.fromJson], // Only EmptyEvent, not AlternativeEvent
      );
      return ProcessResult.error(
        'Expected callEntityDynamic to throw due to type mismatch but it did not',
      );
    } catch (e) {
      entityDynamicWrongTypeError = e as Error;
      return ProcessResult.ok('Caught type mismatch error as expected');
    }
  }

  Future<ProcessResult> handleServiceDynamicWrongType(
    TriggerServiceDynamicWrongTypeEvent event,
    ProcessContext context,
  ) async {
    try {
      await context.callServiceDynamic(
        name: 'TestService',
        cmd: WrongTypeCommand(),
        fac: [EmptyEvent.fromJson], // Only EmptyEvent, not AlternativeEvent
      );
      return ProcessResult.error(
        'Expected callServiceDynamic to throw due to type mismatch but it did not',
      );
    } catch (e) {
      serviceDynamicWrongTypeError = e as Error;
      return ProcessResult.ok('Caught type mismatch error as expected');
    }
  }

  Future<ProcessResult> handleProcessUnhandledException(
    TriggerProcessUnhandledExceptionEvent event,
    ProcessContext context,
  ) async {
    // This handler throws an unhandled exception directly
    throw Exception(
      'Process handler intentionally threw an unhandled exception',
    );
  }

  @override
  void registerFuncs(ProcessFuncs funcs) {
    funcs
      ..add<TriggerEntityThrowEvent>(
        handleEntityThrow,
        TriggerEntityThrowEvent.fromJson,
      )
      ..add<TriggerEntityWrongTypeEvent>(
        handleEntityWrongType,
        TriggerEntityWrongTypeEvent.fromJson,
      )
      ..add<TriggerServiceThrowEvent>(
        handleServiceThrow,
        TriggerServiceThrowEvent.fromJson,
      )
      ..add<TriggerServiceWrongTypeEvent>(
        handleServiceWrongType,
        TriggerServiceWrongTypeEvent.fromJson,
      )
      ..add<TriggerEntityDynamicWrongTypeEvent>(
        handleEntityDynamicWrongType,
        TriggerEntityDynamicWrongTypeEvent.fromJson,
      )
      ..add<TriggerServiceDynamicWrongTypeEvent>(
        handleServiceDynamicWrongType,
        TriggerServiceDynamicWrongTypeEvent.fromJson,
      )
      ..add<TriggerProcessUnhandledExceptionEvent>(
        handleProcessUnhandledException,
        TriggerProcessUnhandledExceptionEvent.fromJson,
      );
  }
}

// ============================================================================
// Tests
// ============================================================================

void main() {
  group('ProcessContext error handling -', () {
    late HordaServerTestSystem system;
    late TestProcessGroup process;

    setUp(() async {
      system = HordaServerTestSystem();
      process = TestProcessGroup();

      system.registerEntity<TestEntityState>(
        TestEntity(),
        TestEntityViewGroup(),
      );
      system.registerService(TestService());
      system.registerProcessGroup(process);

      await system.start();

      // Create the entity
      system.sendEntity(
        'TestEntity',
        'test1',
        'system',
        TestCreateCommand(),
      );

      // Wait for entity creation
      await Future.delayed(Duration(milliseconds: 10));
    });

    test('callEntity should throw when entity handler throws', () async {
      final result = await system.dispatchEvent(
        'system',
        TriggerEntityThrowEvent(),
      );

      expect(result.isError, false);
      expect(result.value, 'Caught error as expected');
      expect(process.entityThrowError, isNotNull);
      expect(process.entityThrowError, isA<FluirError>());
      expect(
        process.entityThrowError.toString(),
        contains('TestEntity'),
      );
      expect(
        process.entityThrowError.toString(),
        contains('handler error'),
      );
      expect(
        process.entityThrowError.toString(),
        contains('intentionally threw an error'),
      );
    });

    test(
      'callEntity should throw when handler returns wrong event type',
      () async {
        final result = await system.dispatchEvent(
          'system',
          TriggerEntityWrongTypeEvent(),
        );

        expect(result.isError, false);
        expect(result.value, 'Caught type mismatch error as expected');
        expect(process.entityWrongTypeError, isNotNull);
        expect(process.entityWrongTypeError, isA<FluirError>());
        expect(
          process.entityWrongTypeError.toString(),
          contains('TestEntity'),
        );
        expect(
          process.entityWrongTypeError.toString(),
          contains('returned unexpected event type AlternativeEvent'),
        );
        expect(
          process.entityWrongTypeError.toString(),
          contains('expected: EmptyEvent'),
        );
      },
    );

    test('callService should throw when service handler throws', () async {
      final result = await system.dispatchEvent(
        'system',
        TriggerServiceThrowEvent(),
      );

      expect(result.isError, false);
      expect(result.value, 'Caught error as expected');
      expect(process.serviceThrowError, isNotNull);
      expect(process.serviceThrowError, isA<FluirError>());
      expect(
        process.serviceThrowError.toString(),
        contains('TestService'),
      );
      expect(
        process.serviceThrowError.toString(),
        contains('handler error'),
      );
      expect(
        process.serviceThrowError.toString(),
        contains('intentionally threw an error'),
      );
    });

    test(
      'callService should throw when handler returns wrong event type',
      () async {
        final result = await system.dispatchEvent(
          'system',
          TriggerServiceWrongTypeEvent(),
        );

        expect(result.isError, false);
        expect(result.value, 'Caught type mismatch error as expected');
        expect(process.serviceWrongTypeError, isNotNull);
        expect(process.serviceWrongTypeError, isA<FluirError>());
        expect(
          process.serviceWrongTypeError.toString(),
          contains('TestService'),
        );
        expect(
          process.serviceWrongTypeError.toString(),
          contains('returned unexpected event type AlternativeEvent'),
        );
        expect(
          process.serviceWrongTypeError.toString(),
          contains('expected: EmptyEvent'),
        );
      },
    );

    test(
      'callEntityDynamic should throw when handler returns wrong event type',
      () async {
        final result = await system.dispatchEvent(
          'system',
          TriggerEntityDynamicWrongTypeEvent(),
        );

        expect(result.isError, false);
        expect(result.value, 'Caught type mismatch error as expected');
        expect(process.entityDynamicWrongTypeError, isNotNull);
        expect(process.entityDynamicWrongTypeError, isA<FluirError>());
        expect(
          process.entityDynamicWrongTypeError.toString(),
          contains('TestEntity'),
        );
        expect(
          process.entityDynamicWrongTypeError.toString(),
          contains('returned unexpected event type AlternativeEvent'),
        );
        expect(
          process.entityDynamicWrongTypeError.toString(),
          contains('expected one of: [EmptyEvent]'),
        );
      },
    );

    test(
      'callServiceDynamic should throw when handler returns wrong event type',
      () async {
        final result = await system.dispatchEvent(
          'system',
          TriggerServiceDynamicWrongTypeEvent(),
        );

        expect(result.isError, false);
        expect(result.value, 'Caught type mismatch error as expected');
        expect(process.serviceDynamicWrongTypeError, isNotNull);
        expect(process.serviceDynamicWrongTypeError, isA<FluirError>());
        expect(
          process.serviceDynamicWrongTypeError.toString(),
          contains('TestService'),
        );
        expect(
          process.serviceDynamicWrongTypeError.toString(),
          contains('returned unexpected event type AlternativeEvent'),
        );
        expect(
          process.serviceDynamicWrongTypeError.toString(),
          contains('expected one of: [EmptyEvent]'),
        );
      },
    );

    test(
      'callEntity should throw even when expected event has no fields (edge case)',
      () async {
        // This is the critical edge case: EmptyEvent has no fields (empty JSON)
        // Before the fix, FluirErrorEvent could be deserialized as EmptyEvent
        // because both have empty JSON. This test verifies the fix works.
        final result = await system.dispatchEvent(
          'system',
          TriggerEntityThrowEvent(),
        );

        expect(result.isError, false);
        expect(result.value, 'Caught error as expected');
        expect(process.entityThrowError, isNotNull);
        expect(process.entityThrowError, isA<FluirError>());
        expect(
          process.entityThrowError.toString(),
          contains('handler error'),
        );
      },
    );

    test(
      'unhandled exception in process handler should be caught and returned as ProcessResult.error',
      () async {
        final result = await system.dispatchEvent(
          'system',
          TriggerProcessUnhandledExceptionEvent(),
        );

        expect(result.isError, true);
        expect(
          result.value,
          contains(
            'Process handler intentionally threw an unhandled exception',
          ),
        );
      },
    );
  });
}
