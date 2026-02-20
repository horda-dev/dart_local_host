import 'dart:async';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';
import 'package:stack_trace/stack_trace.dart';
import 'package:xid/xid.dart';

import 'change_id.dart';
import 'entity.dart';
import 'http.dart';
import 'process.dart';
import 'scheduler.dart';
import 'service.dart';
import 'store.dart';

typedef EntityHostFactory = EntityHost Function(String entityId);

final class HordaServerSystem {
  HordaServerSystem() {
    logger = Logger('Horda.System');

    messageStore = MemoryMessageStore(this);

    keyValueStore = MemKeyValueStore();

    viewStore = MemoryViewStore(
      keyValueStore,
      messageStore,
    );

    httpServer = HttpServer(
      system: this,
    );

    scheduler = Scheduler(this);
  }

  late final MessageStore messageStore;

  late final KeyValueStore keyValueStore;

  late final ViewStore viewStore;

  late final HttpServer httpServer;

  final changeIdTracker = ChangeIdTracker();

  late final Scheduler scheduler;

  late final Logger logger;

  Future<void> start() async {
    logger.fine('starting server system...');

    kRegisterFluirMessage();

    await keyValueStore.start();

    viewStore.startProjectingChanges(messageStore.allViewChanges);

    httpServer.start();

    logger.info('server system started');
  }

  Future<void> stop() async {
    logger.fine('stopping server system...');

    scheduler.cancelAll();

    stopEntities();
    stopServices();
    stopProcesses();

    viewStore.stopProjectingChanges();

    await keyValueStore.stop();

    logger.info('server system stopped');
  }

  /// Generates a unique key for entity host storage.
  /// Combines entityName and entityId to ensure each entity type has its own ID namespace.
  /// This allows multiple singleton entities to coexist (e.g., "ConfigEntity:singleton", "SettingsEntity:singleton").
  String _entityHostKey(String entityName, EntityId entityId) =>
      '$entityName:$entityId';

  void _startEntityHost(EntityId entityId, String entityName) {
    final key = _entityHostKey(entityName, entityId);

    if (_entityHosts.containsKey(key)) {
      throw FluirError('entity host with id "$entityId" already started');
    }

    final factory = _entityHostFactories[entityName];

    if (factory == null) {
      throw FluirError(
        'entity with name "$entityName" has not been registered',
      );
    }

    _entityHosts[key] = factory(entityId);
  }

  void registerEntity<S extends EntityState>(
    Entity<S> entity,
    EntityViewGroup defaultViewGroup,
  ) {
    if (_entityHostFactories.containsKey(entity.name)) {
      throw FluirError('entity ${entity.name} already registered');
    }

    _entityHostFactories[entity.name] = (entityId) {
      return EntityHost<S>(entityId, entity, defaultViewGroup, this);
    };

    // Initialize default view values
    final defaultViews = DefaultViews();
    defaultViewGroup.initViews(defaultViews);
    viewStore.initEntityViews(
      entity.name,
      '__default',
      defaultViews.defaultValues,
    );

    // Pre-create singleton entities immediately with ID = kSingletonId
    if (entity.singleton != null) {
      logger.fine(
        'Pre-creating singleton entity ${entity.name} with ID=$kSingletonId',
      );
      _startEntityHost(kSingletonId, entity.name);
      logger.info(
        'Singleton entity ${entity.name} pre-created and ready with ID=$kSingletonId',
      );
    }
  }

  void stopEntities() {
    for (final entity in _entityHosts.values) {
      entity.stop();
    }
  }

  void removeEntity(String entityName, EntityId entityId) {
    final key = _entityHostKey(entityName, entityId);
    _entityHosts.remove(key);
  }

  void registerService(
    Service service,
  ) {
    if (_serviceHosts.containsKey(service.name)) {
      throw FluirError('service ${service.name} already registered');
    }

    _serviceHosts[service.name] = ServiceHost(service, this);
  }

  void stopServices() {
    for (final service in _serviceHosts.values) {
      service.stop();
    }
  }

  void registerProcessGroup(ProcessGroup processGroup) async {
    final name = processGroup.runtimeType.toString();
    if (_processGroupHosts.containsKey(name)) {
      throw FluirError('process group $name already registered');
    }

    final host = ProcessGroupHost(processGroup, this);
    final eventTypes = host.getRegisteredEventTypes();

    // Check for overlapping event handlers across process groups
    final conflicts = <String, String>{};
    for (final eventType in eventTypes) {
      if (_processEventHandlers.containsKey(eventType)) {
        conflicts[eventType] = _processEventHandlers[eventType]!;
      }
    }

    if (conflicts.isNotEmpty) {
      final conflictDetails = conflicts.entries
          .map((e) => '  - ${e.key} (already handled by ${e.value})')
          .join('\n');
      throw FluirError(
        'Process group $name has overlapping event handlers with other process groups:\n$conflictDetails',
      );
    }

    // Register event types for this process group
    for (final eventType in eventTypes) {
      _processEventHandlers[eventType] = name;
    }

    _processGroupHosts[name] = host;
  }

  void stopProcesses() {
    for (final process in _processGroupHosts.values) {
      process.stop();
    }
  }

  String sendEntity(
    String entityName,
    EntityId entityId,
    EntityId from,
    RemoteCommand cmd,
  ) {
    final key = _entityHostKey(entityName, entityId);

    if (!_entityHosts.containsKey(key)) {
      _startEntityHost(entityId, entityName);
    }

    return messageStore.sendEntity(entityName, entityId, from, cmd);
  }

  String sendEntityJson(
    String entityName,
    EntityId entityId,
    EntityId from,
    String cmdType,
    Map<String, dynamic> cmdJson,
  ) {
    final key = _entityHostKey(entityName, entityId);

    if (!_entityHosts.containsKey(key)) {
      _startEntityHost(entityId, entityName);
    }

    return messageStore.sendEntityJson(
      entityName,
      entityId,
      from,
      cmdType,
      cmdJson,
    );
  }

  Future<E> callEntity<E extends RemoteEvent>({
    required String entityName,
    required EntityId entityId,
    required EntityId from,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  }) {
    final key = _entityHostKey(entityName, entityId);

    if (!_entityHosts.containsKey(key)) {
      _startEntityHost(entityId, entityName);
    }

    return messageStore.callEntity<E>(
      entityName: entityName,
      entityId: entityId,
      from: from,
      cmd: cmd,
      fac: fac,
    );
  }

  Future<RemoteEvent> callEntityDynamic({
    required String entityName,
    required EntityId entityId,
    required EntityId from,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  }) {
    final key = _entityHostKey(entityName, entityId);

    if (!_entityHosts.containsKey(key)) {
      _startEntityHost(entityId, entityName);
    }

    return messageStore.callEntityDynamic(
      entityName: entityName,
      entityId: entityId,
      from: from,
      cmd: cmd,
      fac: fac,
    );
  }

  String sendService(String serviceName, EntityId from, RemoteCommand cmd) {
    return messageStore.sendService(serviceName, from, cmd);
  }

  Future<E> callService<E extends RemoteEvent>({
    required String serviceName,
    required EntityId from,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  }) {
    return messageStore.callService<E>(
      serviceName: serviceName,
      from: from,
      cmd: cmd,
      fac: fac,
    );
  }

  Future<RemoteEvent> callServiceDynamic({
    required String serviceName,
    required EntityId from,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  }) {
    return messageStore.callServiceDynamic(
      serviceName: serviceName,
      from: from,
      cmd: cmd,
      fac: fac,
    );
  }

  Future<ProcessResult> dispatchEvent(
    EntityId from,
    RemoteEvent event,
  ) async {
    return await messageStore.dispatchEvent(from, event);
  }

  Future<ProcessResult> dispatchEventJson(
    EntityId from,
    String eventType,
    Map<String, dynamic> eventJson,
  ) async {
    return await messageStore.dispatchEventJson(from, eventType, eventJson);
  }

  Stream<CommandEnvelop> entityCommands(String entityName, EntityId entityId) {
    return messageStore.entityCommands(entityName, entityId);
  }

  Stream<CommandEnvelop> serviceCommands(String serviceName) {
    return messageStore.serviceCommands(serviceName);
  }

  void publishEntityEvent(EventEnvelop env) {
    messageStore.publishEntityEvent(env);
  }

  void publishServiceEvent(EventEnvelop env) {
    messageStore.publishServiceEvent(env);
  }

  void publishViewChange(ChangeEnvelop env) {
    messageStore.publishViewChange(env);
  }

  void publishManyViewChanges(Iterable<ChangeEnvelop> changes) {
    for (final change in changes) {
      messageStore.publishViewChange(change);
    }
  }

  void publishProcessResult(ProcessResultEnvelop env) {
    messageStore.publishProcessResult(env);
  }

  // startAt is a query change version which
  // we want to start getting events at
  Stream<ChangeEnvelop> queryChanges({
    required String entityName,
    required String id,
    required String name,
    String startAt = '',
  }) {
    return messageStore.queryChanges(
      entityName: entityName,
      id: id,
      name: name,
      startAt: startAt,
    );
  }

  Stream<EventEnvelop> entityEvents({
    String? entityName,
    EntityId? entityId,
    Type? type,
    String? commandId,
  }) {
    return messageStore.entityEvents(
      entityName: entityName,
      entityId: entityId,
      type: type,
      commandId: commandId,
    );
  }

  /// Stream of dispatched events. This stream contains both events dispatched by
  /// the client and events scheduled by entities.
  ///
  /// Events from this stream trigger client and scheduled processes.
  Stream<EventEnvelop> dispatchedEvents() {
    return messageStore.dispatchedEvents();
  }

  Future<String?> runAuthProcess(AuthEvent authEvent) async {
    final env = EventEnvelop(
      actorId: '',
      eventId: Xid().toString(),
      commandId: '',
      type: authEvent.eventType,
      event: authEvent.payload,
    );

    for (final processGroup in _processGroupHosts.values) {
      if (processGroup.canHandle(env)) {
        final result = await processGroup.handle(env);

        if (result.isError) {
          throw AuthException('auth process failed: ${result.value}');
        }

        final userId = result.value;

        if (userId != null && userId.isNotEmpty) {
          return userId;
        }

        return null;
      }
    }

    throw AuthException(
      'no process registered for auth event type: ${authEvent.eventType}',
    );
  }

  Stream<ProcessResultEnvelop> processResults({String? dispatchId}) {
    return messageStore.processResults(dispatchId: dispatchId);
  }

  final _entityHostFactories = <String, EntityHostFactory>{};

  final _entityHosts = <EntityId, EntityHost>{};
  final _processGroupHosts = <String, ProcessGroupHost>{};
  final _serviceHosts = <String, ServiceHost>{};

  // Tracks which process group handles which event types to detect overlaps
  final _processEventHandlers =
      <String, String>{}; // event type -> process group name
}

final class HordaServerTestSystem extends HordaServerSystem {
  HordaServerTestSystem() : super();

  @override
  Future<void> start() async {
    viewStore.startProjectingChanges(messageStore.allViewChanges);

    logger.info('server test system started');
  }
}

class HordaLocalHostError extends Error {
  HordaLocalHostError(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}

class HordaLocalHostJsonError extends Error {
  HordaLocalHostJsonError({
    required String className,
    required String error,
    required StackTrace stacktrace,
  }) {
    final trace = Trace.from(stacktrace);
    if (trace.frames.isEmpty) {
      msg = '$className.fromJson() failed: $error';
      return;
    }

    // First frame should be located at the fromJson factory.
    final location = trace.frames.first.location;
    msg = '$className.fromJson() failed: $error; At $location';
  }

  late final String msg;

  @override
  String toString() => msg;

  Map<String, dynamic> toJson() {
    return {'msg': msg};
  }
}
