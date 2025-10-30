import 'dart:async';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';

import 'cron.dart';
import 'system.dart';

class ProcessHost {
  ProcessHost(
    this.process,
    this._system,
  ) : logger = Logger('Horda.Process.${process.runtimeType}') {
    logger.fine('$name host starting...');

    _handlers = _ProcessHandlers(this, logger);
    process.initHandlers(_handlers);

    _sub = _system.dispatchedEvents().listen(_handleEvent);

    logger.info('$name host started');
  }

  final Process process;
  final HordaServerSystem _system;
  final Logger logger;

  String get name => process.runtimeType.toString();

  void stop() {
    logger.fine('$name host stopping...');

    _sub.cancel();

    logger.info('$name host stopped');
  }

  Future<void> _handleEvent(EventEnvelop env) async {
    if (!_handlers.canHandle(env)) {
      logger.fine('skipped unsupported event: ${env.type}');
      return;
    }

    final result = await _handlers.handle(env);

    _system.publishProcessResult(
      // When dispatching, dispatchId is set as eventId in the EventEnvelope, so dispatchId == eventId.
      // It's done to be able to match the dispatched event with the process result.
      ProcessResultEnvelop(env.eventId, result),
    );
  }

  late final _ProcessHandlers _handlers;
  late final StreamSubscription<EventEnvelop> _sub;
}

class _ProcessHandlers implements ProcessHandlers {
  _ProcessHandlers(this.host, this.logger);

  final ProcessHost host;
  final Logger logger;

  @override
  void add<E extends RemoteEvent>(
    ProcessHandler<E> handler,
    FromJsonFun<E> fromJson,
  ) {
    logger.fine('Adding handler for $E');

    _processHandlers[E] = handler;
    _eventFactories[E.toString()] = fromJson;
  }

  bool canHandle(EventEnvelop env) {
    return _eventFactories.containsKey(env.type);
  }

  Future<ProcessResult> handle(EventEnvelop env) async {
    logger.info(
      'handling event ${env.type} from ${env.actorId}',
    );

    final event = _eventFromJson(env.type, env.event);

    final handler = _processHandlers[event.runtimeType];
    if (handler == null) {
      throw HordaLocalHostError(
        '${host.name} host has no handler registered for event type: ${env.type}',
      );
    }

    final senderId = env.actorId.isNotEmpty ? env.actorId : null;

    final context = _ProcessContext(env.eventId, senderId, host);

    final result = await handler(event, context);

    logger.info('handled ${env.type} from ${env.actorId}');

    return result;
  }

  RemoteEvent _eventFromJson(String type, Map<String, dynamic> json) {
    final fac = _eventFactories[type];
    if (fac == null) {
      throw HordaLocalHostError(
        '${host.name} host has no json factory registered for event type: $type',
      );
    }

    try {
      final cmd = fac(json);

      return cmd;
    } catch (e, stacktrace) {
      throw HordaLocalHostJsonError(
        className: type,
        error: e.toString(),
        stacktrace: stacktrace,
      );
    }
  }

  final _processHandlers = <Type, dynamic>{};
  final _eventFactories = <String, dynamic>{};
}

class _ProcessContext implements ProcessContext {
  _ProcessContext(this.processId, this.senderId, this.host);

  @override
  final String processId;

  @override
  final String? senderId;

  DateTime get clock => DateTime.now().toUtc();

  Logger get logger => host.logger;

  final ProcessHost host;

  // Entity methods
  @override
  Future<E> callEntity<E extends RemoteEvent>({
    required String name,
    required EntityId id,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  }) async {
    return await host._system.callEntity<E>(
      entityName: name,
      entityId: id,
      from: processId,
      cmd: cmd,
      fac: fac,
    );
  }

  @override
  Future<RemoteEvent> callEntityDynamic({
    required String name,
    required EntityId id,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  }) async {
    return await host._system.callEntityDynamic(
      entityName: name,
      entityId: id,
      from: processId,
      cmd: cmd,
      fac: fac,
    );
  }

  @override
  void sendEntity({
    required String name,
    required EntityId id,
    required RemoteCommand cmd,
  }) {
    host._system.sendEntity(name, id, processId, cmd);
  }

  @override
  Future<String> scheduleEntity({
    required String name,
    required EntityId id,
    required Duration after,
    required RemoteCommand cmd,
  }) async {
    final scheduleCmd = Schedule.entity(name, id, clock.add(after), cmd);
    final event = await callService<Scheduled>(
      name: 'CronService',
      cmd: scheduleCmd,
      fac: Scheduled.fromJson,
    );
    return event.cancelId;
  }

  @override
  void unscheduleEntity({
    required String name,
    required String scheduleId,
  }) async {
    sendService(
      name: 'CronService',
      cmd: Cancel(scheduleId),
    );
  }

  @override
  Future<E> callService<E extends RemoteEvent>({
    required String name,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  }) async {
    return await host._system.callService<E>(
      serviceName: name,
      from: processId,
      cmd: cmd,
      fac: fac,
    );
  }

  @override
  Future<RemoteEvent> callServiceDynamic({
    required String name,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  }) async {
    return await host._system.callServiceDynamic(
      serviceName: name,
      from: processId,
      cmd: cmd,
      fac: fac,
    );
  }

  @override
  void sendService({
    required String name,
    required RemoteCommand cmd,
  }) {
    host._system.sendService(name, processId, cmd);
  }

  @override
  Future<String> scheduleService({
    required String name,
    required Duration after,
    required RemoteCommand cmd,
  }) async {
    final scheduleCmd = Schedule.service(name, clock.add(after), cmd);
    final event = await callService<Scheduled>(
      name: 'CronService',
      cmd: scheduleCmd,
      fac: Scheduled.fromJson,
    );
    return event.cancelId;
  }

  @override
  void unscheduleService({
    required String name,
    required String scheduleId,
  }) async {
    sendService(
      name: 'CronService',
      cmd: Cancel(scheduleId),
    );
  }
}

class ProcessResultEnvelop {
  const ProcessResultEnvelop(this.dispatchId, this.result);

  final String dispatchId;
  final ProcessResult result;
}
