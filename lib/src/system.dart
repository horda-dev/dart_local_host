import 'dart:async';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';
import 'package:quiver/async.dart';
import 'package:stack_trace/stack_trace.dart';

import 'change_id.dart';
import 'cron.dart';
import 'entity.dart';
import 'http.dart';
import 'process.dart';
import 'service.dart';
import 'store.dart';

typedef EntityHostFactory = EntityHost Function(String entityId);

final class HordaServerSystem {
  HordaServerSystem() {
    logger = Logger('Horda.System');

    messageStore = MemoryMessageStore(this);

    keyValueStore = MemKeyValueStore();

    viewStore = MemoryViewStore(
      messageStore,
      keyValueStore,
    );

    httpServer = HttpServer(
      system: this,
    );
  }

  late final MessageStore messageStore;

  late final KeyValueStore keyValueStore;

  late final ViewStore viewStore;

  late final HttpServer httpServer;

  final changeIdTracker = ChangeIdTracker();

  late final Logger logger;

  Future<void> start() async {
    logger.fine('starting server system...');

    kRegisterFluirMessage();
    kRegisterCronMessages();

    await keyValueStore.start();

    viewStore.startProjectingChanges(messageStore.allChanges);

    registerService(CronService(this));

    _tickerSub = _ticker.listen(
      (now) => sendService('CronService', 'system', Tick(now)),
    );

    httpServer.start();

    logger.info('server system started');
  }

  Future<void> stop() async {
    logger.fine('stopping server system...');

    _tickerSub?.cancel();

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

    final defaultViews = DefaultViews();
    defaultViewGroup.initViews(defaultViews);
    viewStore.setViewDefaults(entity.name, defaultViews.defaultValues);

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

  void registerProcess(Process process) async {
    final name = process.runtimeType.toString();
    if (_processHosts.containsKey(name)) {
      throw FluirError('service $name already registered');
    }

    _processHosts[name] = ProcessHost(process, this);
  }

  void stopProcesses() {
    for (final process in _processHosts.values) {
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

  Future<FlowResult> dispatchEvent(
    EntityId from,
    RemoteEvent event,
  ) async {
    return await messageStore.dispatchEvent(from, event);
  }

  Future<FlowResult> dispatchEventJson(
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

  void publishChange(ChangeEnvelop env) {
    messageStore.publishChange(env);
  }

  void publishManyChanges(Iterable<ChangeEnvelop> changes) {
    for (final change in changes) {
      messageStore.publishChange(change);
    }
  }

  void publishProcessResult(ProcessResultEnvelop env) {
    messageStore.publishProcessResult(env);
  }

  // startAt is a view state version which
  // we want to start getting events at
  Stream<ChangeEnvelop> changes({
    required String entityName,
    required String id,
    required String name,
    String startAt = '',
  }) {
    return messageStore.changes(
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

  Stream<EventEnvelop> dispatchedEvents() {
    return messageStore.dispatchedEvents();
  }

  Stream<ProcessResultEnvelop> processResults({String? dispatchId}) {
    return messageStore.processResults(dispatchId: dispatchId);
  }

  final _entityHostFactories = <String, EntityHostFactory>{};

  final _entityHosts = <EntityId, EntityHost>{};
  final _processHosts = <String, ProcessHost>{};
  final _serviceHosts = <String, ServiceHost>{};

  final _ticker = Metronome.epoch(
    const Duration(seconds: 1),
  );

  StreamSubscription<DateTime>? _tickerSub;
}

final class HordaServerTestSystem extends HordaServerSystem {
  HordaServerTestSystem() : super();

  @override
  Future<void> start() async {
    viewStore.startProjectingChanges(messageStore.allChanges);

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
