import 'dart:async';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'log.dart';
import 'process.dart';
import 'system.dart';

/// Wrapper for entity commands that includes the entity name for routing.
/// This is needed to support multiple singleton entities with the same ID.
class _EntityCommandEnvelope {
  _EntityCommandEnvelope(this.entityName, this.command);

  final String entityName;
  final CommandEnvelop command;
}

abstract class MessageStore {
  String sendEntity(
    String entityName,
    EntityId entityId,
    EntityId from,
    RemoteCommand cmd,
  );

  String sendEntityJson(
    String entityName,
    EntityId entityId,
    EntityId from,
    String cmdType,
    Map<String, dynamic> cmdJson,
  );

  Future<E> callEntity<E extends RemoteEvent>({
    required String entityName,
    required EntityId entityId,
    required EntityId from,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  });

  Future<RemoteEvent> callEntityDynamic({
    required String entityName,
    required EntityId entityId,
    required EntityId from,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  });

  Stream<CommandEnvelop> entityCommands(String entityName, EntityId entityId);

  Stream<EventEnvelop> entityEvents({
    String? entityName,
    EntityId? entityId,
    Type? type,
    String? commandId,
  });

  String sendService(String serviceName, EntityId from, RemoteCommand cmd);

  Future<E> callService<E extends RemoteEvent>({
    required String serviceName,
    required EntityId from,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  });

  Future<RemoteEvent> callServiceDynamic({
    required String serviceName,
    required EntityId from,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  });

  Stream<CommandEnvelop> serviceCommands(String serviceName);

  Stream<EventEnvelop> serviceEvents({
    String? serviceName,
    Type? type,
    String? commandId,
  });

  Future<FlowResult> dispatchEvent(
    EntityId from,
    RemoteEvent event,
  );

  Future<FlowResult> dispatchEventJson(
    EntityId from,
    String eventType,
    Map<String, dynamic> eventJson,
  );

  void publishEntityEvent(EventEnvelop event);

  void publishServiceEvent(EventEnvelop event);

  void publishProcessResult(ProcessResultEnvelop result);

  void publishChange(ChangeEnvelop change);

  Stream<EventEnvelop> dispatchedEvents();

  /// Returns a stream of [ProcessResultEnvelop] for a provided [dispatchId].
  /// [dispatchId] - id of
  Stream<ProcessResultEnvelop> processResults({
    String? dispatchId,
  });

  // those methods bellow must go to view store

  /// Returns an [Iterable] which contains either one [ChangeEnvelop] which contains all past changes,
  /// or one empty [ChangeEnvelop] if there's no history.
  Iterable<ChangeEnvelop> changeHistory({
    required String entityName,
    required EntityId id,
    required String name,
    required String startAt,
  });

  Stream<ChangeEnvelop> changes({
    required String entityName,
    required EntityId id,
    required String name,
    String startAt,
  });

  Stream<ChangeEnvelop> get allChanges;
}

class MemoryMessageStore implements MessageStore {
  MemoryMessageStore(this.system) : logger = Logger('Fluir.MessageStore');

  final HordaServerSystem system;

  final Logger logger;

  @override
  String sendEntity(
    String entityName,
    EntityId entityId,
    EntityId from,
    RemoteCommand cmd,
  ) {
    logger.fine(
      'sending entity command $cmd to $entityName/$entityId, from: $from...',
    );

    final env = CommandEnvelop(
      to: entityId,
      from: from,
      commandId: _nextCmdId.toString(),
      type: cmd.runtimeType.toString(),
      command: cmd.toJson(),
      replyFlow: ReplyFlow.none(),
      replyClient: ReplyClient.none(),
    );

    _saveCommand(entityName, env);
    _entityCommands.add(_EntityCommandEnvelope(entityName, env));
    _nextCmdId += 1;

    logger.info('sent entity envelop $env to $entityName/$entityId from $from');

    return env.commandId;
  }

  @override
  String sendEntityJson(
    String entityName,
    EntityId entityId,
    EntityId from,
    String cmdType,
    Map<String, dynamic> cmdJson,
  ) {
    logger.fine(
      'sending entity command (json) $cmdType to $entityName/$entityId, from: $from...',
    );

    final env = CommandEnvelop(
      to: entityId,
      from: from,
      commandId: _nextCmdId.toString(),
      type: cmdType,
      command: cmdJson,
      replyFlow: ReplyFlow.none(),
      replyClient: ReplyClient.none(),
    );

    _saveCommand(entityName, env);
    _entityCommands.add(_EntityCommandEnvelope(entityName, env));
    _nextCmdId += 1;

    logger.info(
        'sent entity envelop (json) $env to $entityName/$entityId from $from');

    return env.commandId;
  }

  @override
  Future<E> callEntity<E extends RemoteEvent>({
    required String entityName,
    required EntityId entityId,
    required EntityId from,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  }) async {
    final cmdId = sendEntity(entityName, entityId, from, cmd);
    final eventEnv = await entityEvents(entityId: entityId, commandId: cmdId)
        .timeout(const Duration(milliseconds: 500))
        .first;
    return fac(eventEnv.event);
  }

  @override
  Future<RemoteEvent> callEntityDynamic({
    required String entityName,
    required EntityId entityId,
    required EntityId from,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  }) async {
    // Build factory map from event type to factory
    final factoryMap = <String, FromJsonFun<RemoteEvent>>{
      for (final factory in fac)
        // Function return type is always the last word in the runtimeType string
        factory.runtimeType.toString().split(' ').last: factory,
    };

    final cmdId = sendEntity(entityName, entityId, from, cmd);
    final eventEnv = await entityEvents(entityId: entityId, commandId: cmdId)
        .timeout(const Duration(milliseconds: 500))
        .first;

    final factory = factoryMap[eventEnv.type];
    if (factory == null) {
      throw FluirError(
        'No factory registered for event type ${eventEnv.type} for entity $entityName/$entityId',
      );
    }

    return factory(eventEnv.event);
  }

  @override
  Stream<CommandEnvelop> entityCommands(String entityName, EntityId entityId) {
    logger.fine('getting entity commands for $entityName/$entityId...');

    // Use composite key for command storage to support multiple singletons
    var logId = '$entityName:$entityId';
    var log = _commandStore[logId] ?? [];

    var past = Stream<CommandEnvelop>.fromIterable([...log]);
    // Filter by both entityName and entityId to support multiple singletons
    var future = _entityCommands.stream
        .where((e) => e.entityName == entityName && e.command.to == entityId)
        .map((e) => e.command);

    logger.info(
        'got ${log.length} past entity commands for $entityName/$entityId');

    return Rx.concatEager([
      past,
      future,
    ]);
  }

  @override
  Stream<EventEnvelop> entityEvents({
    String? entityName,
    EntityId? entityId,
    Type? type,
    String? commandId,
  }) {
    var res = _entityEvents.stream;

    if (entityId != null) {
      res = res.where((e) => e.actorId == entityId);
      logger.fine('getting entity events by entity id "$entityId" started');
    }

    if (type != null) {
      res = res.where((e) => e.event.runtimeType == type);
      logger.fine('getting entity events by type "$type" started');
    }

    if (commandId != null) {
      res = res.where((e) => e.commandId == commandId);
      logger.info('getting entity events by command id "$commandId" started');
    }

    return res;
  }

  @override
  String sendService(String serviceName, EntityId from, RemoteCommand cmd) {
    logger.fine('sending service command $cmd to $serviceName, from: $from...');

    final env = CommandEnvelop(
      to: serviceName,
      from: from,
      commandId: _nextCmdId.toString(),
      type: cmd.runtimeType.toString(),
      command: cmd.toJson(),
      replyFlow: ReplyFlow.none(),
      replyClient: ReplyClient.none(),
    );

    _saveCommand(null, env); // null for service commands
    _serviceCommands.add(env);
    _nextCmdId += 1;

    logger.info(
      'sent service envelop ${limitString(env)} to $serviceName from $from',
    );

    return env.commandId;
  }

  @override
  Future<E> callService<E extends RemoteEvent>({
    required String serviceName,
    required EntityId from,
    required RemoteCommand cmd,
    required FromJsonFun<E> fac,
  }) async {
    final cmdId = sendService(serviceName, from, cmd);
    final eventEnv =
        await serviceEvents(serviceName: serviceName, commandId: cmdId)
            .timeout(const Duration(seconds: 10))
            .first;
    return fac(eventEnv.event);
  }

  @override
  Future<RemoteEvent> callServiceDynamic({
    required String serviceName,
    required EntityId from,
    required RemoteCommand cmd,
    required List<FromJsonFun<RemoteEvent>> fac,
  }) async {
    // Build factory map from event type to factory
    final factoryMap = <String, FromJsonFun<RemoteEvent>>{
      for (final factory in fac)
        // Function return type is always the last word in the runtimeType string
        factory.runtimeType.toString().split(' ').last: factory,
    };

    final cmdId = sendService(serviceName, from, cmd);
    final eventEnv =
        await serviceEvents(serviceName: serviceName, commandId: cmdId)
            .timeout(const Duration(seconds: 10))
            .first;

    final factory = factoryMap[eventEnv.type];
    if (factory == null) {
      throw FluirError(
        'No factory registered for event type ${eventEnv.type} for service $serviceName',
      );
    }

    return factory(eventEnv.event);
  }

  @override
  Stream<CommandEnvelop> serviceCommands(String serviceName) {
    logger.fine('getting service commands for $serviceName...');

    var logId = serviceName;
    var log = _commandStore[logId] ?? [];

    var past = Stream<CommandEnvelop>.fromIterable([...log]);
    var future = _serviceCommands.stream.where((e) => e.to == serviceName);

    logger.info('got ${log.length} past service commands for $serviceName');

    return Rx.concatEager([
      past,
      future,
    ]);
  }

  @override
  Stream<EventEnvelop> serviceEvents({
    String? serviceName,
    Type? type,
    String? commandId,
  }) {
    var res = _serviceEvents.stream;

    if (serviceName != null) {
      res = res.where((e) => e.actorId == serviceName);
      logger.fine(
          'getting service events by service name "$serviceName" started');
    }

    if (type != null) {
      res = res.where((e) => e.event.runtimeType == type);
      logger.fine('getting service events by type "$type" started');
    }

    if (commandId != null) {
      res = res.where((e) => e.commandId == commandId);
      logger.info('getting service events by command id "$commandId" started');
    }

    return res;
  }

  @override
  Future<FlowResult> dispatchEvent(
    EntityId from,
    RemoteEvent event,
  ) async {
    final dispatchId = _dispatchEvent(from, event);
    final resultEnv = await processResults(dispatchId: dispatchId)
        .timeout(const Duration(seconds: 10))
        .first;
    return resultEnv.result;
  }

  @override
  Future<FlowResult> dispatchEventJson(
    EntityId from,
    String eventType,
    Map<String, dynamic> eventJson,
  ) async {
    final dispatchId = _dispatchEventJson(from, eventType, eventJson);
    final resultEnv = await processResults(dispatchId: dispatchId)
        .timeout(const Duration(seconds: 10))
        .first;
    return resultEnv.result;
  }

  @override
  void publishEntityEvent(EventEnvelop event) {
    logger.fine('publishing entity event $event...');

    _entityEvents.add(event);

    logger.info('published entity event $event');
  }

  @override
  void publishServiceEvent(EventEnvelop event) {
    logger.fine('publishing service event $event...');

    _serviceEvents.add(event);

    logger.info('published service event $event');
  }

  @override
  void publishProcessResult(ProcessResultEnvelop result) {
    logger.fine('publishing flow result $result...');

    _processResults.add(result);

    logger.info('published flow result $result');
  }

  @override
  void publishChange(ChangeEnvelop change) {
    logger.fine('publishing change $change...');

    _saveChange(change);
    _changes.add(change);

    logger.info('published change $change');
  }

  @override
  Stream<EventEnvelop> dispatchedEvents() {
    return _dispatchedEvents.stream;
  }

  @override
  Stream<ProcessResultEnvelop> processResults({
    String? dispatchId,
  }) {
    var res = _processResults.stream;

    if (dispatchId != null) {
      res = res.where((e) => e.dispatchId == dispatchId);
      logger.fine('getting flow results by dispatch id "$dispatchId" started');
    }

    return res;
  }

  @override
  Iterable<ChangeEnvelop> changeHistory({
    required String entityName,
    required EntityId id,
    required String name,
    required String startAt,
  }) {
    final fullName = 'for $id/$name starting at $startAt';

    logger.fine('changes: getting for $fullName starting at $startAt...');

    final logId = _viewOrAttrKey(entityName, id, name);
    final log = _changeStore[logId];
    if (log == null) {
      logger.info('changes: no log found for $fullName');
      return [
        ChangeEnvelop.empty(entityName: entityName, key: id, name: name),
      ];
    }

    final startAtChId = ChangeId.fromString(startAt);
    final idx = log.indexWhere(
      (e) => ChangeId.fromString(e.changeId) > startAtChId,
    );
    if (idx == -1) {
      logger.info(
        'changes: no changes found for $fullName starting at $startAt',
      );
      return [
        ChangeEnvelop.empty(entityName: entityName, key: id, name: name),
      ];
    }

    final range = log.getRange(idx, log.length);

    logger.info(
      'changes: got ${range.length} changes for $fullName starting at $startAt',
    );

    return [...range];
  }

  // startAt is a view state version which
  // we want to start getting changes at
  @override
  Stream<ChangeEnvelop> changes({
    required String entityName,
    required EntityId id,
    required String name,
    String startAt = '',
  }) {
    Stream<ChangeEnvelop> past;
    if (startAt != '-1') {
      past = Stream.fromIterable(
        // Make stream from a copy of log to avoid 'Concurrent Modification' exception
        [
          ...changeHistory(
            entityName: entityName,
            id: id,
            name: name,
            startAt: startAt,
          )
        ],
      );
    } else {
      past = const Stream.empty();
    }

    final future = _changes.stream.where(
      (e) => e.entityName == entityName && e.key == id && e.name == name,
    );

    return Rx.concatEager([past, future]);
  }

  @override
  Stream<ChangeEnvelop> get allChanges {
    return _changes.stream;
  }

  String _dispatchEvent(EntityId from, RemoteEvent event) {
    logger.fine('dispatching $event from: $from...');

    final env = EventEnvelop(
      actorId: from,
      eventId: _nextDispatchId.toString(),
      commandId: '0', // command id is always 0 when dispatching events
      type: event.runtimeType.toString(),
      event: event.toJson(),
    );

    _dispatchedEvents.add(env);
    _nextDispatchId += 1;

    logger.info('dispatched $env from $from');

    return env.eventId;
  }

  String _dispatchEventJson(
    EntityId from,
    String eventType,
    Map<String, dynamic> eventJson,
  ) {
    logger.fine('dispatching (json) $eventType from: $from...');

    final env = EventEnvelop(
      actorId: from,
      eventId: _nextDispatchId.toString(),
      commandId: '0', // command id is always 0 when dispatching events
      type: eventType,
      event: eventJson,
    );

    _dispatchedEvents.add(env);
    _nextDispatchId += 1;

    logger.info('dispatched (json) $env from $from');

    return env.eventId;
  }

  void _saveCommand(String? entityName, CommandEnvelop command) {
    // For entity commands, use composite key (entityName:entityId) to support multiple singletons
    // For service commands, entityName is null and we use just the service name
    var logId = entityName != null ? '$entityName:${command.to}' : command.to;
    var log = _commandStore[logId] ?? [];

    logger.fine('saving command ${limitString(command)} to $logId...');

    log.add(command);
    _commandStore.putIfAbsent(logId, () => log);

    logger.info('saved command ${limitString(command)} to $logId');
  }

  void _saveChange(ChangeEnvelop e) {
    if (e.changes.isEmpty) {
      return;
    }

    final logId = _viewOrAttrKey(e.entityName, e.key, e.name);

    final log = _changeStore[logId] ?? [];

    logger.fine('adding changes $e to $logId...');

    if (log.isEmpty) {
      log.add(e);
      _changeStore[logId] = log;

      logger.info('added changes $e to $logId');

      return;
    }

    final lastChangeId = ChangeId.fromString(log.last.changeId);
    final addingChangeId = ChangeId.fromString(e.changeId);

    if (lastChangeId >= addingChangeId) {
      logger.warning(
        'tried adding a change envelope with ChangeId less than last ChangeId in the store',
      );
      return;
    }

    log.add(e);

    logger.info('added changes $e to $logId');

    _changeStore.putIfAbsent(logId, () => log);
  }

  String _viewOrAttrKey(String entityName, EntityId id, String name) {
    if (entityName.isEmpty) {
      return '$id/$name';
    }

    return '$entityName/$id/$name';
  }

  // maps actor id to command log
  final _commandStore = <EntityId, List<CommandEnvelop>>{};
  // maps actor id to change log
  final _changeStore = <EntityId, List<ChangeEnvelop>>{};

  // unique command id to find corresponding event
  var _nextCmdId = 1;
  // unique command id to find corresponding process result
  var _nextDispatchId = 1;

  final _entityCommands = StreamController<_EntityCommandEnvelope>.broadcast();
  final _entityEvents = StreamController<EventEnvelop>.broadcast();
  final _serviceCommands = StreamController<CommandEnvelop>.broadcast();
  final _serviceEvents = StreamController<EventEnvelop>.broadcast();
  final _dispatchedEvents = StreamController<EventEnvelop>.broadcast();
  final _processResults = StreamController<ProcessResultEnvelop>.broadcast();
  final _changes = StreamController<ChangeEnvelop>.broadcast();
}

abstract class ViewStore {
  void startProjectingChanges(Stream<ChangeEnvelop> changes);

  void stopProjectingChanges();

  Future<void> setViewDefaults(String entityName, List<DefaultViewValue> views);

  Future<void> initEntityViews(
    String entityName,
    EntityId entityId,
    List<InitViewData> views,
  );

  /// Throws if not found.
  Future<ViewSnapshot> viewSnapshot(
    String entityName,
    EntityId entityId,
    String viewName,
  );

  /// Throws if not found.
  Future<ViewSnapshot> attributeSnapshot(String from, String to, String name);

  Future<QueryResult> query({
    required String actorId,
    required String name,
    required QueryDef query,
  });

  Future<void> seed(Map<String, dynamic> seed);
}

/// Determines the count of changes to be stored before caching view value.
const kViewCacheByCountCondition = 10;

/// Determines the amount of time which should pass before view value is cached.
const kViewCacheByTimeCondition = Duration(seconds: 2);

class MemoryViewStore implements ViewStore {
  MemoryViewStore(this.messageStore, this.snapStore)
      : logger = Logger('Horda.ViewStore');

  final Logger logger;

  final MessageStore messageStore;

  final KeyValueStore snapStore;

  @override
  void startProjectingChanges(Stream<ChangeEnvelop> changes) {
    _viewUpdaterSub?.cancel();
    _viewUpdaterSub = changes.listen(_project);
  }

  @override
  void stopProjectingChanges() {
    _viewUpdaterSub?.cancel();
  }

  @override
  Future<void> setViewDefaults(
    String entityName,
    List<DefaultViewValue> views,
  ) async {
    for (final view in views) {
      await snapStore.set(
        '$entityName/__default/${view.name}',
        ViewSnapshot(view.value, ''),
      );
    }
  }

  @override
  Future<void> initEntityViews(
    String entityName,
    EntityId entityId,
    List<InitViewData> views,
  ) async {
    for (final view in views) {
      final snapKey = '$entityName/${view.key}/${view.name}';

      await snapStore.set(
        snapKey,
        ViewSnapshot(view.value, ''),
      );
    }
  }

  @override
  Future<ViewSnapshot> viewSnapshot(
    String entityName,
    EntityId entityId,
    String viewName,
  ) async {
    late final ViewSnapshot snap;

    try {
      final viewKey = '$entityName/$entityId/$viewName';
      snap = await snapStore.get(viewKey);
    } on FluirError {
      final defaultKey = '$entityName/__default/$viewName';
      snap = await snapStore.get(defaultKey);
    }

    return snap;
  }

  @override
  Future<ViewSnapshot> attributeSnapshot(
    String from,
    String to,
    String name,
  ) async {
    final cid = CompositeId(from, to);
    final attrKey = '${cid.id}/$name';
    return await snapStore.get(attrKey);
  }

  @override
  Future<void> seed(Map<String, dynamic> seed) async {
    var views = <String, ViewSnapshot>{};

    for (var entry in seed.entries) {
      var vid = entry.key;
      views[vid] = ViewSnapshot.fromJson(entry.value);
    }

    snapStore.seed(views);
  }

  @override
  Future<QueryResult> query({
    required String actorId,
    required String name,
    required QueryDef query,
  }) async {
    Future<QueryResultBuilder> visitQuery(
      QueryDef query,
      EntityId actorId,
    ) async {
      final qr = QueryResultBuilder();

      for (final entry in query.views.entries) {
        final name = entry.key;
        final view = entry.value;

        final viewSnap = await viewSnapshot(query.entityName, actorId, name);

        if (view is ValueQueryDef) {
          qr.add(ValueQueryResultBuilder(name, viewSnap));
        } else if (view is RefQueryDef) {
          if (viewSnap.isNull) {
            // no attrs and subquery run for null ref
            qr.add(RefQueryResultBuilder(name, viewSnap, {}, null));
            continue;
          }

          // getting attributes values if requested
          final attrs = <String, dynamic>{};
          for (final attr in view.attrs) {
            final attrSnap = await attributeSnapshot(
              actorId,
              viewSnap.value,
              attr,
            );
            attrs[attr] = attrSnap.toJson();
          }

          // running subquery
          final subquery = await visitQuery(view.query, viewSnap.value);
          final res = RefQueryResultBuilder(
            name,
            viewSnap,
            attrs,
            subquery,
          );
          qr.add(res);
        } else if (view is ListQueryDef) {
          final items = <QueryResultBuilder>[];
          // maps itemId to {'attrName': attrValue}
          final allAttrs = <String, Map<String, dynamic>>{};

          for (final itemId in viewSnap.value as List<EntityId>) {
            // getting attr values for item id
            final itemAttrs = <String, dynamic>{};
            for (final attrName in view.attrs) {
              final attrSnap = await attributeSnapshot(
                actorId,
                itemId,
                attrName,
              );
              itemAttrs[attrName] = attrSnap.toJson();
            }

            if (itemAttrs.isNotEmpty) {
              allAttrs[itemId] = itemAttrs;
            }

            // running subquery for item id
            items.add(
              await visitQuery(view.query, itemId),
            );
          }

          qr.add(
            ListQueryResultBuilder(entry.key, allAttrs, viewSnap, items),
          );
        } else {
          throw FluirError('unknown query def ${view.runtimeType}');
        }
      }

      return qr;
    }

    final res = await visitQuery(query, actorId);
    return res.build();
  }

  void _project(ChangeEnvelop env) async {
    final isAttrChange = env.entityName.isEmpty;
    final snapKey = isAttrChange
        ? '${env.key}/${env.name}'
        : '${env.entityName}/${env.key}/${env.name}';

    logger.fine('View store got a change from stream, with key: $snapKey');

    final currentSnap = await snapStore.get(snapKey);

    logger.finer(
      'Projecting ${env.sourceId}, old ver: ${currentSnap.changeId}, env ver: ${env.changeId}, count: ${env.changes.length}',
    );

    final newSnap = env.isOverwriting
        ? _projectLast(currentSnap, env)
        : _projectAll(currentSnap, env);

    await snapStore.set(snapKey, newSnap);
  }

  ViewSnapshot _projectLast(ViewSnapshot currentSnapshot, ChangeEnvelop env) {
    final lastChange = env.changes.last;

    final newValue = _getProjectedValue(currentSnapshot.value, lastChange);
    final newChangeId = env.changeId;

    return ViewSnapshot(newValue, newChangeId);
  }

  ViewSnapshot _projectAll(ViewSnapshot currentSnapshot, ChangeEnvelop env) {
    var newValue = currentSnapshot.value;
    final newChangeId = env.changeId;

    for (final change in env.changes) {
      newValue = _getProjectedValue(newValue, change);
    }

    return ViewSnapshot(newValue, newChangeId);
  }

  dynamic _getProjectedValue(dynamic currentValue, Change change) {
    return switch (change) {
      // Value
      ValueViewChanged() => change.newValue,
      // Counter
      CounterViewIncremented() => currentValue + change.by,
      CounterViewDecremented() => currentValue - change.by,
      CounterViewReset() => change.newValue,
      // Ref
      RefViewChanged() => change.newValue,
      // List
      ListViewItemAdded() => (currentValue as List<String>)..add(change.itemId),
      ListViewItemAddedIfAbsent() => () {
          currentValue as List<String>;
          if (currentValue.contains(change.itemId)) {
            return currentValue;
          }
          return currentValue..add(change.itemId);
        }(),
      ListViewItemRemoved() => (currentValue as List<String>)
        ..remove(change.itemId),
      ListViewCleared() => (currentValue as List<String>)..clear(),
      // Attr Value
      RefValueAttributeChanged() => change.newValue,
      // Attr Counter
      CounterAttrIncremented() => (currentValue ?? 0) + change.by,
      CounterAttrDecremented() => (currentValue ?? 0) - change.by,
      CounterAttrReset() => change.newValue,
      _ => throw UnsupportedError('Unknown change type ${change.runtimeType}'),
    };
  }

  StreamSubscription<ChangeEnvelop>? _viewUpdaterSub;
}

abstract class KeyValueStore {
  Future<void> start();

  Future<void> stop();

  Future<bool> containsKey(String key);

  Future<ViewSnapshot> get(String key);

  Future<void> set(String key, ViewSnapshot snap);

  Future<void> seed(Map<String, ViewSnapshot> snaps);
}

final class MemKeyValueStore implements KeyValueStore {
  @override
  Future<void> start() async {
    // noop
  }

  @override
  Future<void> stop() async {
    // noop
  }

  @override
  Future<bool> containsKey(String key) async {
    return _store.containsKey(key);
  }

  @override
  Future<ViewSnapshot> get(String key) async {
    final snap = _store[key];
    if (snap == null) {
      throw FluirError('key $key not found');
    }
    return snap;
  }

  @override
  Future<void> set(String key, ViewSnapshot snap) async {
    _store[key] = snap;
  }

  @override
  Future<void> seed(Map<String, ViewSnapshot> snaps) async {
    _store.addAll(snaps);
  }

  final _store = <String, ViewSnapshot>{};
}

/// Used to collect views from [EntityViewGroup], to initialize view defaults for an entity.
class DefaultViews implements ViewGroup {
  @override
  void add(View view) {
    views.add(view);
    defaultValues.add(
      DefaultViewValue(view.name, view.defaultValue),
    );
  }

  final views = <View>[];
  final defaultValues = <DefaultViewValue>[];
}

class DefaultViewValue {
  const DefaultViewValue(this.name, this.value);

  final String name;
  final dynamic value;
}
