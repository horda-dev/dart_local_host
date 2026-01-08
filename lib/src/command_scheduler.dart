import 'dart:collection';

import 'package:horda_server/horda_server.dart';
import 'package:xid/xid.dart';

import 'system.dart';

class CommandScheduler {
  CommandScheduler(this.system);

  final HordaServerSystem system;

  /// Schedules a command to be sent to an entity at the specified time.
  /// Returns a cancelId that can be used to cancel the scheduled command.
  String scheduleEntity({
    required String entityName,
    required EntityId to,
    required DateTime at,
    required RemoteCommand cmd,
  }) {
    final clock = DateTime.now().toUtc();
    if (at.isBefore(clock)) {
      throw CronException(
        'command at $at is before the clock $clock',
      );
    }

    var futureCmd = _FutureEntityCommand(cmd, entityName, to);

    var commands = _scheduleMap.putIfAbsent(
      at,
      () => <_FutureCommand>[],
    );
    commands.add(futureCmd);

    _index[futureCmd.cancelId] = at;

    return futureCmd.cancelId;
  }

  /// Schedules a command to be sent to a service at the specified time.
  /// Returns a cancelId that can be used to cancel the scheduled command.
  String scheduleService({
    required String serviceName,
    required DateTime at,
    required RemoteCommand cmd,
  }) {
    final clock = DateTime.now().toUtc();
    if (at.isBefore(clock)) {
      throw CronException(
        'command at $at is before the clock $clock',
      );
    }

    var futureCmd = _FutureServiceCommand(cmd, serviceName);

    var commands = _scheduleMap.putIfAbsent(
      at,
      () => <_FutureCommand>[],
    );
    commands.add(futureCmd);

    _index[futureCmd.cancelId] = at;

    return futureCmd.cancelId;
  }

  /// Cancels a scheduled command using its cancelId.
  void cancel(String cancelId) {
    final cancelAt = _index[cancelId];

    if (cancelAt == null) {
      throw CronException('no command found for cancel id: $cancelId');
    }

    final commands = _scheduleMap[cancelAt];
    if (commands == null || commands.isEmpty) {
      throw CronException(
        'command for cancel id: $cancelId has been executed already',
      );
    }

    final idx = commands.indexWhere((c) => c.cancelId == cancelId);
    if (idx == -1) {
      throw StateError(
        'index is not consistent with schedule for $cancelId and $cancelAt',
      );
    }

    commands.removeAt(idx);
    _index.remove(cancelId);
  }

  /// Processes all scheduled commands that should run before or at the specified time.
  /// Returns the number of commands sent.
  int tick(DateTime now) {
    var commands = <_FutureCommand>[];
    var keys = <DateTime>[];

    // find commands before now
    for (var entry in _scheduleMap.entries) {
      if (entry.key.isAfter(now)) {
        break;
      }
      commands.addAll(entry.value);
      keys.add(entry.key);
    }

    // send commands
    for (var c in commands) {
      switch (c) {
        case _FutureEntityCommand():
          system.sendEntity(c.entityName, c.entityId, 'CronService', c.cmd);
        case _FutureServiceCommand():
          system.sendService(c.serviceName, 'CronService', c.cmd);
      }
    }

    // update state
    for (var c in commands) {
      _index.remove(c.cancelId);
    }
    for (var k in keys) {
      _scheduleMap.remove(k);
    }

    return commands.length;
  }

  final _scheduleMap = SplayTreeMap<DateTime, List<_FutureCommand>>();

  // maps cancelId to original command at value
  final _index = <String, DateTime>{};
}

abstract class _FutureCommand {
  _FutureCommand(this.cmd) : cancelId = Xid().toString();

  final String cancelId;

  final RemoteCommand cmd;
}

class _FutureEntityCommand extends _FutureCommand {
  _FutureEntityCommand(super.cmd, this.entityName, this.entityId);

  final String entityName;
  final EntityId entityId;
}

class _FutureServiceCommand extends _FutureCommand {
  _FutureServiceCommand(super.cmd, this.serviceName);

  final String serviceName;
}

class CronException implements Exception {
  CronException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
