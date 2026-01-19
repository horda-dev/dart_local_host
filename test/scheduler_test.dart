import 'dart:async';

import 'package:horda_local_host/src/system.dart';
import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

// Test event types
class TestProcessEvent extends RemoteEvent {
  TestProcessEvent();

  @override
  Map<String, dynamic> toJson() => {};

  static TestProcessEvent fromJson(Map<String, dynamic> json) =>
      TestProcessEvent();
}

class AnotherTestProcessEvent extends RemoteEvent {
  AnotherTestProcessEvent();

  @override
  Map<String, dynamic> toJson() => {};

  static AnotherTestProcessEvent fromJson(Map<String, dynamic> json) =>
      AnotherTestProcessEvent();
}

// Test process group to capture dispatched events
class TestProcessGroup extends ProcessGroup {
  static RemoteEvent? lastEventReceived;
  static String? lastSenderId;
  static int eventCount = 0;

  static void reset() {
    lastEventReceived = null;
    lastSenderId = null;
    eventCount = 0;
  }

  @override
  void registerFuncs(ProcessFuncs funcs) {
    funcs.add<TestProcessEvent>(
      (event, context) async {
        lastEventReceived = event;
        lastSenderId = context.senderId;
        eventCount++;
        return ProcessResult.ok();
      },
      TestProcessEvent.fromJson,
    );

    funcs.add<AnotherTestProcessEvent>(
      (event, context) async {
        lastEventReceived = event;
        lastSenderId = context.senderId;
        eventCount++;
        return ProcessResult.ok();
      },
      AnotherTestProcessEvent.fromJson,
    );
  }
}

void main() {
  group('Scheduler', () {
    late HordaServerTestSystem system;

    setUp(() async {
      system = HordaServerTestSystem();
      TestProcessGroup.reset();
      await system.start();
    });

    tearDown(() async {
      await system.stop();
    });

    test('scheduleProcess triggers process handler after delay', () async {
      system.registerProcessGroup(TestProcessGroup());

      final entityId = 'test-entity-1';

      // Schedule event
      final scheduleId = system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: entityId,
      );

      expect(scheduleId, isNotEmpty);

      // Event should not be received yet
      expect(TestProcessGroup.lastEventReceived, isNull);

      // Wait for timer to fire
      await Future.delayed(const Duration(milliseconds: 150));

      // Verify process handler was called with correct event and sender
      expect(TestProcessGroup.lastEventReceived, isA<TestProcessEvent>());
      expect(TestProcessGroup.lastSenderId, equals(entityId));
      expect(TestProcessGroup.eventCount, equals(1));
    });

    test('cancel prevents scheduled event from executing', () async {
      system.registerProcessGroup(TestProcessGroup());

      // Schedule event
      final scheduleId = system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'test-entity-1',
      );

      // Cancel before execution
      system.scheduler.cancel(scheduleId);

      // Wait beyond scheduled time
      await Future.delayed(const Duration(milliseconds: 150));

      // Verify handler was NOT called
      expect(TestProcessGroup.lastEventReceived, isNull);
      expect(TestProcessGroup.eventCount, equals(0));
    });

    test('cancel with non-existent scheduleId does not throw', () {
      // Should not throw an error
      expect(
        () => system.scheduler.cancel('non-existent-id'),
        returnsNormally,
      );
    });

    test('multiple scheduled events execute independently', () async {
      system.registerProcessGroup(TestProcessGroup());

      // Schedule multiple events at different times
      system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 50),
        scheduledBy: 'entity-1',
      );

      system.scheduler.scheduleProcess(
        event: AnotherTestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-2',
      );

      system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 150),
        scheduledBy: 'entity-3',
      );

      // Wait for all to complete
      await Future.delayed(const Duration(milliseconds: 200));

      // All three events should have been processed
      expect(TestProcessGroup.eventCount, equals(3));
    });

    test('schedule returns unique IDs for each schedule', () {
      final id1 = system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-1',
      );

      final id2 = system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-1',
      );

      final id3 = system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-2',
      );

      expect(id1, isNot(equals(id2)));
      expect(id1, isNot(equals(id3)));
      expect(id2, isNot(equals(id3)));
    });

    test('cancelAll cancels all pending schedules', () async {
      system.registerProcessGroup(TestProcessGroup());

      // Schedule multiple events
      system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-1',
      );

      system.scheduler.scheduleProcess(
        event: AnotherTestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-2',
      );

      system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-3',
      );

      // Cancel all
      system.scheduler.cancelAll();

      // Wait beyond scheduled time
      await Future.delayed(const Duration(milliseconds: 150));

      // Verify no handlers were called
      expect(TestProcessGroup.lastEventReceived, isNull);
      expect(TestProcessGroup.eventCount, equals(0));
    });

    test('scheduled event preserves sender ID', () async {
      system.registerProcessGroup(TestProcessGroup());

      const schedulerEntityId = 'my-custom-entity-123';

      system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 50),
        scheduledBy: schedulerEntityId,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Verify the sender ID is preserved
      expect(TestProcessGroup.lastSenderId, equals(schedulerEntityId));
    });

    test('scheduler handles immediate execution (Duration.zero)', () async {
      system.registerProcessGroup(TestProcessGroup());

      system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: Duration.zero,
        scheduledBy: 'entity-1',
      );

      // Give it a tiny bit of time to execute
      await Future.delayed(const Duration(milliseconds: 10));

      expect(TestProcessGroup.lastEventReceived, isA<TestProcessEvent>());
      expect(TestProcessGroup.eventCount, equals(1));
    });

    test('canceling already-executed schedule does not throw', () async {
      system.registerProcessGroup(TestProcessGroup());

      final scheduleId = system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 50),
        scheduledBy: 'entity-1',
      );

      // Wait for execution
      await Future.delayed(const Duration(milliseconds: 100));

      // Cancel after it has already executed
      expect(
        () => system.scheduler.cancel(scheduleId),
        returnsNormally,
      );
    });

    test('system stop cancels all pending schedules', () async {
      system.registerProcessGroup(TestProcessGroup());

      // Schedule events
      system.scheduler.scheduleProcess(
        event: TestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-1',
      );

      system.scheduler.scheduleProcess(
        event: AnotherTestProcessEvent(),
        after: const Duration(milliseconds: 100),
        scheduledBy: 'entity-2',
      );

      // Stop the system (which calls scheduler.cancelAll())
      await system.stop();

      // Wait beyond scheduled time
      await Future.delayed(const Duration(milliseconds: 150));

      // Verify no handlers were called
      expect(TestProcessGroup.eventCount, equals(0));
    });
  });
}
