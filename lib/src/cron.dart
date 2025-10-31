import 'dart:collection';

import 'package:horda_server/horda_server.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xid/xid.dart';

import 'system.dart';

part 'cron.g.dart';

//
// commands
//

// sealed
abstract class CronCommand extends RemoteCommand {}

class Schedule extends CronCommand {
  Schedule(this.entityName, this.to, this.serviceName, this.at, this.cmd);

  Schedule.entity(this.entityName, this.to, this.at, this.cmd)
    : serviceName = '';
  Schedule.service(this.serviceName, this.at, this.cmd)
    : entityName = '',
      to = '';

  final String entityName;
  final EntityId to;

  final String serviceName;

  final DateTime at;

  final RemoteCommand cmd;

  @override
  String format() {
    if (entityName.isNotEmpty) {
      return '$entityName/$to, ${cmd.runtimeType}';
    }
    return '$serviceName, ${cmd.runtimeType}';
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      json['entityName'],
      json['to'],
      json['serviceName'],
      DateTime.fromMillisecondsSinceEpoch(json['at']),
      kMessageFromJson(json['type'], json['cmd']),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'entityName': entityName,
      'to': to,
      'serviceName': serviceName,
      'at': at.millisecondsSinceEpoch,
      'type': cmd.runtimeType.toString(),
      'cmd': cmd.toJson(),
    };
  }
}

@JsonSerializable()
class Cancel extends CronCommand {
  Cancel(this.cancelId);

  final String cancelId;

  factory Cancel.fromJson(Map<String, dynamic> json) {
    return _$CancelFromJson(json);
  }

  @override
  Map<String, dynamic> toJson() {
    return _$CancelToJson(this);
  }
}

@JsonSerializable()
@DateTimeJsonConverter()
class Tick extends CronCommand {
  Tick(this.now);

  final DateTime now;

  factory Tick.fromJson(Map<String, dynamic> json) {
    return _$TickFromJson(json);
  }

  @override
  Map<String, dynamic> toJson() {
    return _$TickToJson(this);
  }
}

//
// events
//

abstract class CronEvent extends RemoteEvent {}

@JsonSerializable()
class Scheduled extends CronEvent {
  Scheduled(this.cancelId);

  // use it to cancel scheduled command
  final String cancelId;

  @override
  String format() => cancelId;

  factory Scheduled.fromJson(Map<String, dynamic> json) {
    return _$ScheduledFromJson(json);
  }

  @override
  Map<String, dynamic> toJson() {
    return _$ScheduledToJson(this);
  }
}

@JsonSerializable()
class CronTicked extends CronEvent {
  CronTicked(this.sent);

  // number of commands sent for this tick
  final int sent;

  factory CronTicked.fromJson(Map<String, dynamic> json) {
    return _$CronTickedFromJson(json);
  }

  @override
  Map<String, dynamic> toJson() {
    return _$CronTickedToJson(this);
  }
}

@JsonSerializable()
class Canceled extends CronEvent {
  Canceled(this.cancelId);

  final String cancelId;

  @override
  String format() => cancelId;

  factory Canceled.fromJson(Map<String, dynamic> json) {
    return _$CanceledFromJson(json);
  }

  @override
  Map<String, dynamic> toJson() {
    return _$CanceledToJson(this);
  }
}

class CronService implements Service {
  CronService(this.system);

  final HordaServerSystem system;

  @override
  String get name => 'CronService';

  @override
  void initHandlers(ServiceHandlers handlers) {
    handlers.add<Schedule>(_schedule, Schedule.fromJson);
    handlers.add<Cancel>(_cancel, Cancel.fromJson);
    handlers.add<Tick>(_tick, Tick.fromJson);
  }

  Future<CronEvent> _schedule(Schedule cmd, ServiceContext context) async {
    if (cmd.at.isBefore(context.clock)) {
      throw CronException(
        'command at ${cmd.at} is before the clock ${context.clock}',
      );
    }

    var futureCmd = cmd.entityName.isNotEmpty
        ? _FutureEntityCommand(cmd.cmd, cmd.entityName, cmd.to)
        : _FutureServiceCommand(cmd.cmd, cmd.serviceName);

    var commands = _scheduleMap.putIfAbsent(
      cmd.at,
      () => <_FutureCommand>[],
    );
    commands.add(futureCmd);

    _index[futureCmd.cancelId] = cmd.at;

    return Scheduled(
      futureCmd.cancelId,
    );
  }

  Future<CronEvent> _cancel(Cancel cmd, ServiceContext context) async {
    final cancelAt = _index[cmd.cancelId];

    if (cancelAt == null) {
      throw CronException('no command found for cancel id: ${cmd.cancelId}');
    }

    final commands = _scheduleMap[cancelAt];
    if (commands == null || commands.isEmpty) {
      throw CronException(
        'command for cancel id: ${cmd.cancelId} has been executed already',
      );
    }

    final idx = commands.indexWhere((c) => c.cancelId == cmd.cancelId);
    if (idx == -1) {
      throw StateError(
        'index is not consistent with schedule for ${cmd.cancelId} and $cancelAt',
      );
    }

    commands.removeAt(idx);
    _index.remove(cmd.cancelId);

    return Canceled(
      cmd.cancelId,
    );
  }

  Future<CronEvent> _tick(Tick cmd, ServiceContext context) async {
    var commands = <_FutureCommand>[];
    var keys = <DateTime>[];

    // find commands before now
    for (var entry in _scheduleMap.entries) {
      if (entry.key.isAfter(cmd.now)) {
        break;
      }
      commands.addAll(entry.value);
      keys.add(entry.key);
    }

    // send commands
    for (var c in commands) {
      switch (c) {
        case _FutureEntityCommand():
          system.sendEntity(c.entityName, c.entityId, 'CronService', cmd);
        case _FutureServiceCommand():
          system.sendService(c.serviceName, 'CronService', cmd);
      }
    }

    // update state
    for (var c in commands) {
      _index.remove(c.cancelId);
    }
    for (var k in keys) {
      _scheduleMap.remove(k);
    }

    return CronTicked(
      commands.length,
    );
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

void kRegisterCronMessages() {
  kRegisterMessageFactory<Schedule>(Schedule.fromJson);
  kRegisterMessageFactory<Cancel>(Cancel.fromJson);
  kRegisterMessageFactory<Tick>(Tick.fromJson);
  kRegisterMessageFactory<Scheduled>(Scheduled.fromJson);
  kRegisterMessageFactory<CronTicked>(CronTicked.fromJson);
  kRegisterMessageFactory<Canceled>(Canceled.fromJson);
}
