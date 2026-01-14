import 'dart:async';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';
import 'package:xid/xid.dart';

import 'system.dart';

/// Scheduler for process events using Dart's built-in Timer.
///
/// This class provides simple timer-based scheduling for process events.
/// Each scheduled event gets a unique ID that can be used for cancellation.
class Scheduler {
  Scheduler(this.system) : logger = Logger('Horda.Scheduler');

  final HordaServerSystem system;
  final Logger logger;

  /// Schedules a process event to be dispatched after a delay.
  ///
  /// Returns a scheduleId that can be used to cancel the scheduled event.
  ///
  /// The [scheduledBy] parameter specifies which entity is scheduling the event,
  /// and this entity ID will be used as the sender when the event is dispatched.
  String scheduleProcess({
    required Duration after,
    required RemoteEvent event,
    required EntityId scheduledBy,
  }) {
    final scheduleId = Xid().toString();

    logger.fine(
      'scheduling ${event.runtimeType} by $scheduledBy after ${after.inMilliseconds}ms, scheduleId: $scheduleId',
    );

    final timer = Timer(after, () {
      logger.info(
        'dispatching scheduled ${event.runtimeType} by $scheduledBy, scheduleId: $scheduleId',
      );
      // Dispatch event with the entity that scheduled it as sender
      system.messageStore.dispatchEvent(scheduledBy, event);
      _timers.remove(scheduleId);
    });

    _timers[scheduleId] = timer;

    return scheduleId;
  }

  /// Cancels a scheduled process event.
  ///
  /// If the schedule ID doesn't exist (already executed or never scheduled),
  /// this method does nothing (not an error).
  void cancel(String scheduleId) {
    final timer = _timers.remove(scheduleId);
    if (timer == null) {
      logger.fine(
        'cancel scheduleId: $scheduleId (already executed or not found)',
      );
      // Already executed or never existed - not an error
      return;
    }
    logger.info('cancelled scheduleId: $scheduleId');
    timer.cancel();
  }

  /// Cancels all pending schedules.
  ///
  /// This is useful for cleanup during shutdown.
  void cancelAll() {
    final count = _timers.length;
    logger.info('cancelling all $count pending schedules');
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  final _timers = <String, Timer>{};
}
