import 'dart:async';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';

import 'system.dart';

class ServiceHost {
  ServiceHost(
    this.service,
    this._system,
  ) : logger = Logger('Horda.Service.${service.runtimeType}') {
    logger.fine('name: ${service.name} starting...');

    _handlers = _ServiceHandlers(service.name, this, logger);
    service.initHandlers(_handlers);

    _sub = _system.serviceCommands(service.name).listen(_handleCommand);

    logger.info('name: ${service.name} started');
  }

  final Service service;

  final Logger logger;

  void stop() {
    logger.fine('name: ${service.name} stopping...');

    _sub.cancel();

    logger.info('name: ${service.name} stopped');
  }

  void _handleCommand(CommandEnvelop env) async {
    try {
      logger.fine('name: ${service.name} processing $env...');

      final event = await _handlers.handle(env);

      _system.publishServiceEvent(
        EventEnvelop(
          actorId: service.name,
          // Make eventId == commandId for easier matching when debugging.
          eventId: env.commandId,
          commandId: env.commandId,
          type: event.runtimeType.toString(),
          event: event.toJson(),
        ),
      );

      logger.info('name: ${service.name} processed $env');
    } catch (e) {
      logger.severe('name: ${service.name} processed $env with error: $e');

      final errorEvent = FluirErrorEvent(e.toString());

      _system.publishServiceEvent(
        EventEnvelop(
          actorId: service.name,
          // Make eventId == commandId for easier matching when debugging.
          eventId: env.commandId,
          commandId: env.commandId,
          type: errorEvent.runtimeType.toString(),
          event: errorEvent.toJson(),
        ),
      );
    }
  }

  final HordaServerSystem _system;

  late final _ServiceHandlers _handlers;
  late final StreamSubscription<CommandEnvelop> _sub;
}

class _ServiceHandlers implements ServiceHandlers {
  _ServiceHandlers(this.serviceName, this.host, this.logger);

  final ServiceHost host;

  final String serviceName;

  final Logger logger;

  @override
  void add<C extends RemoteCommand>(
    ServiceHandler<C> handler,
    FromJsonFun<C> fromJson,
  ) {
    logger.fine('Adding handler for $C');

    _serviceHandlers[C] = handler;
    _commandFactories[C.toString()] = fromJson;
  }

  Future<RemoteEvent> handle(CommandEnvelop env) async {
    logger.info(
      'Handling command ${env.type} from ${env.from} to ${env.to}',
    );

    final context = _ServiceContext(env.from, host);

    final cmd = _commandFromJson(env.type, env.command);
    final handler = _serviceHandlers[cmd.runtimeType];

    if (handler == null) {
      throw HordaLocalHostError(
        'service $serviceName has no handler registered for command type: ${cmd.runtimeType}',
      );
    }

    final event = await handler(cmd, context);

    return event as RemoteEvent;
  }

  RemoteCommand _commandFromJson(String type, Map<String, dynamic> json) {
    final fac = _commandFactories[type];
    if (fac == null) {
      throw HordaLocalHostError(
        'service $serviceName has no json factory registered for command type: $type',
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

  final _serviceHandlers = <Type, dynamic>{};
  final _commandFactories = <String, dynamic>{};
}

class _ServiceContext implements ServiceContext {
  _ServiceContext(this.senderId, this.host);

  final ServiceHost host;

  @override
  final EntityId senderId;

  @override
  DateTime get clock => DateTime.now().toUtc();

  Logger get logger => host.logger;
}
