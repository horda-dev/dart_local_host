import 'dart:async';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:xid/xid.dart';

import 'list_view_page.dart';
import 'log.dart';
import 'process.dart';
import 'system.dart';

/// Global counter for generating list item positions
double _listPositionCounter = 0.0;

/// Generates a new unique position value for list items
double _nextListPosition() => ++_listPositionCounter;

/// Result of getting a range from a list view snapshot.
/// Contains the list items and the positions for the boundaries.
class ListViewRange {
  ListViewRange({
    required this.items,
    required this.startAfterPos,
    required this.endBeforePos,
  });

  final List<ListItem> items;
  final double startAfterPos;
  final double endBeforePos;
}

/// Key for identifying a view across the system.
/// Consists of [entityName], [entityId], and [viewName].
class ViewKey {
  const ViewKey(this.entityName, this.entityId, this.viewName);

  final String entityName;
  final String entityId;
  final String viewName;

  @override
  String toString() {
    // Makes sense when the key is for an attribute. It should have no entity name.
    if (entityName.isEmpty) {
      return '$entityId/$viewName';
    }
    return '$entityName/$entityId/$viewName';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewKey &&
          runtimeType == other.runtimeType &&
          entityName == other.entityName &&
          entityId == other.entityId &&
          viewName == other.viewName;

  @override
  int get hashCode =>
      entityName.hashCode ^ entityId.hashCode ^ viewName.hashCode;
}

/// Result of a query for atomic query and subscribe operation.
/// Contains the query result, change IDs for all views, and list pages.
class QueryForSubscriptionResult {
  QueryForSubscriptionResult(this.queryResult, this.changeIDs, this.pages);

  final QueryResult queryResult;

  /// ChangeIDs for queried views must be used to create subscriptions.
  final Map<ViewKey, String> changeIDs;

  /// Pages must be added to the page manager to perform real-time sync of queried list view pages.
  final List<ListViewPage> pages;
}

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

  Future<ProcessResult> dispatchEvent(
    EntityId from,
    RemoteEvent event,
  );

  Future<ProcessResult> dispatchEventJson(
    EntityId from,
    String eventType,
    Map<String, dynamic> eventJson,
  );

  void publishEntityEvent(EventEnvelop event);

  void publishServiceEvent(EventEnvelop event);

  void publishProcessResult(ProcessResultEnvelop result);

  void publishViewChange(ChangeEnvelop change);

  void publishQueryChange(ChangeEnvelop change);

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

  Stream<ChangeEnvelop> queryChanges({
    required String entityName,
    required EntityId id,
    required String name,
    String startAt,
  });

  Stream<ChangeEnvelop> get allQueryChanges;

  Stream<ChangeEnvelop> get allViewChanges;
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
      'sent entity envelop (json) $env to $entityName/$entityId from $from',
    );

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
    final eventEnv = await entityEvents(
      entityId: entityId,
      commandId: cmdId,
    ).timeout(const Duration(milliseconds: 500)).first;

    // Check if the handler threw an error
    if (eventEnv.type == 'FluirErrorEvent') {
      final errorMsg = eventEnv.event['msg'] as String;
      throw FluirError(
        'Entity $entityName/$entityId handler error: $errorMsg',
      );
    }

    // Check if the returned event type matches the expected type
    final expectedType = E.toString();
    if (eventEnv.type != expectedType) {
      throw FluirError(
        'Entity $entityName/$entityId returned unexpected event type ${eventEnv.type}, expected: $expectedType',
      );
    }

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
    final eventEnv = await entityEvents(
      entityId: entityId,
      commandId: cmdId,
    ).timeout(const Duration(milliseconds: 500)).first;

    // Check if the handler threw an error
    if (eventEnv.type == 'FluirErrorEvent') {
      final errorMsg = eventEnv.event['msg'] as String;
      throw FluirError(
        'Entity $entityName/$entityId handler error: $errorMsg',
      );
    }

    final factory = factoryMap[eventEnv.type];
    if (factory == null) {
      throw FluirError(
        'Entity $entityName/$entityId returned unexpected event type ${eventEnv.type}, expected one of: ${factoryMap.keys.toList()}',
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
      'got ${log.length} past entity commands for $entityName/$entityId',
    );

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
    final eventEnv = await serviceEvents(
      serviceName: serviceName,
      commandId: cmdId,
    ).timeout(const Duration(seconds: 10)).first;

    // Check if the handler threw an error
    if (eventEnv.type == 'FluirErrorEvent') {
      final errorMsg = eventEnv.event['msg'] as String;
      throw FluirError(
        'Service $serviceName handler error: $errorMsg',
      );
    }

    // Check if the returned event type matches the expected type
    final expectedType = E.toString();
    if (eventEnv.type != expectedType) {
      throw FluirError(
        'Service $serviceName returned unexpected event type ${eventEnv.type}, expected: $expectedType',
      );
    }

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
    final eventEnv = await serviceEvents(
      serviceName: serviceName,
      commandId: cmdId,
    ).timeout(const Duration(seconds: 10)).first;

    // Check if the handler threw an error
    if (eventEnv.type == 'FluirErrorEvent') {
      final errorMsg = eventEnv.event['msg'] as String;
      throw FluirError(
        'Service $serviceName handler error: $errorMsg',
      );
    }

    final factory = factoryMap[eventEnv.type];
    if (factory == null) {
      throw FluirError(
        'Service $serviceName returned unexpected event type ${eventEnv.type}, expected one of: ${factoryMap.keys.toList()}',
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
        'getting service events by service name "$serviceName" started',
      );
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
  Future<ProcessResult> dispatchEvent(
    EntityId from,
    RemoteEvent event,
  ) async {
    final dispatchId = _dispatchEvent(from, event);
    final resultEnv = await processResults(
      dispatchId: dispatchId,
    ).timeout(const Duration(seconds: 10)).first;
    return resultEnv.result;
  }

  @override
  Future<ProcessResult> dispatchEventJson(
    EntityId from,
    String eventType,
    Map<String, dynamic> eventJson,
  ) async {
    final dispatchId = _dispatchEventJson(from, eventType, eventJson);
    final resultEnv = await processResults(
      dispatchId: dispatchId,
    ).timeout(const Duration(seconds: 10)).first;
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
  void publishViewChange(ChangeEnvelop change) {
    logger.fine('publishing view change $change...');

    _saveChange(change);
    _viewChanges.add(change);

    logger.info('published view change $change');
  }

  @override
  void publishQueryChange(ChangeEnvelop change) {
    logger.fine('publishing query change $change...');

    _saveChange(change);
    _queryChanges.add(change);

    logger.info('published query change $change');
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
  // we want to start getting query changes at
  @override
  Stream<ChangeEnvelop> queryChanges({
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
          ),
        ],
      );
    } else {
      past = const Stream.empty();
    }

    final future = _queryChanges.stream.where(
      (e) => e.entityName == entityName && e.key == id && e.name == name,
    );

    return Rx.concatEager([past, future]);
  }

  @override
  Stream<ChangeEnvelop> get allQueryChanges {
    return _queryChanges.stream;
  }

  @override
  Stream<ChangeEnvelop> get allViewChanges {
    return _viewChanges.stream;
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
  final _viewChanges = StreamController<ChangeEnvelop>.broadcast();
  final _queryChanges = StreamController<ChangeEnvelop>.broadcast();
}

abstract class ViewStore {
  void startProjectingChanges(Stream<ChangeEnvelop> changes);

  void stopProjectingChanges();

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

  /// Executes a query and returns the result, change IDs, and list pages.
  /// The changeIDs map includes views at all nesting levels (from Ref and List queries).
  /// The pages list includes all list view pages created during the query.
  Future<QueryForSubscriptionResult> queryForSubscription({
    required String actorId,
    required String name,
    required QueryDef query,
  });

  Future<void> seed(Map<String, dynamic> seed);

  /// Returns the next item in a list view after the given position.
  /// Returns null if no item exists after the position.
  /// Items are ordered by their position values.
  Future<ListItem?> getNextListItem(
    String entityName,
    EntityId entityId,
    String viewName,
    double afterPos,
  );

  /// Returns the previous item in a list view before the given position.
  /// Returns null if no item exists before the position.
  /// Items are ordered by their position values.
  Future<ListItem?> getPreviousListItem(
    String entityName,
    EntityId entityId,
    String viewName,
    double beforePos,
  );
}

/// Determines the count of changes to be stored before caching view value.
const kViewCacheByCountCondition = 10;

/// Determines the amount of time which should pass before view value is cached.
const kViewCacheByTimeCondition = Duration(seconds: 2);

class MemoryViewStore implements ViewStore {
  MemoryViewStore(this.snapStore, this.messageStore)
    : logger = Logger('Horda.ViewStore');

  final Logger logger;

  final KeyValueStore snapStore;

  final MessageStore messageStore;

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
  Future<void> initEntityViews(
    String entityName,
    EntityId entityId,
    List<InitViewData> views,
  ) async {
    for (final view in views) {
      final snapKey = '$entityName/${view.key}/${view.name}';

      dynamic snapValue = view.value;

      // Create list items with positions for RefListView
      if (view.type == 'RefListView') {
        final items = view.value as List<String>;
        snapValue = items
            .map((refId) => ListItem(_nextListPosition(), refId))
            .toList();
      }

      await snapStore.set(
        snapKey,
        ViewSnapshot(snapValue, ''),
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
    final res = await _visitQuery(
      query,
      actorId,
      // We don't perform subscriptions, so pass null.
      null,
      // We don't perform real-time sync of list view pages, so pass null.
      null,
    );
    return res.build();
  }

  @override
  Future<QueryForSubscriptionResult> queryForSubscription({
    required String actorId,
    required String name,
    required QueryDef query,
  }) async {
    final changeIDs = <ViewKey, String>{};
    final pages = <ListViewPage>[];

    final res = await _visitQuery(
      query,
      actorId,
      changeIDs,
      pages,
    );

    return QueryForSubscriptionResult(res.build(), changeIDs, pages);
  }

  /// Shared recursive query visitor.
  /// If [changeIDs] is provided, collects [ViewKey] -> changeID mappings for all views at all nesting levels.
  /// If [pages] is provided, collects [ListViewPage] objects for all list views at all nesting levels.
  Future<QueryResultBuilder> _visitQuery(
    QueryDef query,
    EntityId actorId,
    Map<ViewKey, String>? changeIDs,
    List<ListViewPage>? pages,
  ) async {
    final qr = QueryResultBuilder();

    for (final entry in query.views.entries) {
      final name = entry.key;
      final view = entry.value;

      final viewSnap = await viewSnapshot(query.entityName, actorId, name);

      // Collect changeID if map provided
      if (changeIDs != null) {
        final viewKey = ViewKey(query.entityName, actorId, name);
        changeIDs[viewKey] = viewSnap.changeId;
      }

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

        // running subquery (recursively collects changeIDs and pages if provided)
        final subquery = await _visitQuery(
          view.query,
          viewSnap.value,
          changeIDs,
          pages,
        );
        final res = RefQueryResultBuilder(
          name,
          viewSnap,
          attrs,
          subquery,
        );
        qr.add(res);
      } else if (view is ListQueryDef) {
        _throwIfInvalidPaginationParams(view);

        final range = _getRangeFromRefListSnapshot(
          viewSnap,
          view.startAfter,
          view.endBefore,
          view.limit,
        );

        var pageId = '';

        if (pages != null) {
          final page = _createListPage(
            ViewKey(query.entityName, actorId, name),
            range.startAfterPos,
            range.endBeforePos,
            view.limit,
            range.items,
          );
          pageId = page.pageId;
          pages.add(page);
        }

        final items = <QueryResultBuilder>[];
        // maps itemId to {'attrName': attrValue}
        final allAttrs = <String, Map<String, dynamic>>{};

        for (final pageItem in range.items) {
          final itemId = pageItem.refId;
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

          // running subquery for item id (recursively collects changeIDs and pages if provided)
          items.add(
            await _visitQuery(view.query, itemId, changeIDs, pages),
          );
        }

        qr.add(
          ListQueryResultBuilder(
            entry.key,
            allAttrs,
            ViewSnapshot(range.items, viewSnap.changeId),
            items,
            pageId,
          ),
        );
      } else {
        throw FluirError('unknown query def ${view.runtimeType}');
      }
    }

    return qr;
  }

  void _project(ChangeEnvelop env) async {
    final isAttrChange = env.entityName.isEmpty;
    final snapKey = isAttrChange
        ? '${env.key}/${env.name}'
        : '${env.entityName}/${env.key}/${env.name}';

    logger.fine('View store got a change from stream, with key: $snapKey');

    ViewSnapshot? currentSnap;
    // Is null if no snapshot is found.
    dynamic currentValue;

    if (isAttrChange) {
      // Here we do not attempt fetching default value, because attributes don't have them.
      // If no snap is found, currentValue is null, attribute change projection must handle this.
      try {
        currentSnap = await snapStore.get(snapKey);
        currentValue = currentSnap.value;
      } on FluirError catch (_) {
        logger.fine(
          'Attribute snapshot not found, attribute will be initialized',
        );
      }
    } else {
      // Here we either fetch the snapshot from the store or fetch the default value.
      // currentValue can not be null when projectig view changes.
      currentSnap = await viewSnapshot(env.entityName, env.key, env.name);
      currentValue = currentSnap.value;
    }

    logger.finer(
      'Projecting ${env.sourceId}, old ver: ${currentSnap?.changeId}, env ver: ${env.changeId}, count: ${env.changes.length}',
    );

    final (newSnap, queryChanges) = env.isOverwriting
        ? _projectLast(currentValue, env)
        : _projectAll(currentValue, env);

    await snapStore.set(snapKey, newSnap);

    // Publish query changes to query stream
    if (queryChanges.isNotEmpty) {
      messageStore.publishQueryChange(
        ChangeEnvelop(
          entityName: env.entityName,
          changeId: env.changeId,
          key: env.key,
          name: env.name,
          changes: queryChanges,
        ),
      );
    }
  }

  (ViewSnapshot, List<Change>) _projectLast(
    dynamic currentValue,
    ChangeEnvelop env,
  ) {
    final lastChange = env.changes.last;

    final (newValue, queryChange) = _projectChange(currentValue, lastChange);
    final newChangeId = env.changeId;

    return (
      ViewSnapshot(newValue, newChangeId),
      [if (queryChange != null) queryChange],
    );
  }

  (ViewSnapshot, List<Change>) _projectAll(
    dynamic currentValue,
    ChangeEnvelop env,
  ) {
    var newValue = currentValue;
    final newChangeId = env.changeId;
    final queryChanges = <Change>[];

    for (final change in env.changes) {
      final (projectedValue, queryChange) = _projectChange(newValue, change);
      newValue = projectedValue;

      // Only add to list if a query change was produced
      if (queryChange != null) {
        queryChanges.add(queryChange);
      }
    }

    return (
      ViewSnapshot(newValue, newChangeId),
      queryChanges,
    );
  }

  (dynamic, Change?) _projectChange(dynamic currentValue, Change change) {
    return switch (change) {
      // Value - pass through
      ValueViewChanged() => (change.newValue, change),

      // Counter - pass through
      CounterViewIncremented() => (currentValue + change.by, change),
      CounterViewDecremented() => (currentValue - change.by, change),
      CounterViewReset() => (change.newValue, change),

      // Ref - pass through
      RefViewChanged() => (change.newValue, change),

      // List - CONVERT to query changes
      ListViewItemAdded() => _projectListItemAdded(currentValue, change),
      ListViewItemRemoved() => _projectListItemRemoved(currentValue, change),
      ListViewCleared() => ((currentValue as List<ListItem>)..clear(), change),

      // Attr Value - pass through
      RefValueAttributeChanged() => (change.newValue, change),

      // Attr Counter - pass through
      CounterAttrIncremented() => ((currentValue ?? 0) + change.by, change),
      CounterAttrDecremented() => ((currentValue ?? 0) - change.by, change),
      CounterAttrReset() => (change.newValue, change),

      _ => throw UnsupportedError('Unknown change type ${change.runtimeType}'),
    };
  }

  (List<ListItem>, Change?) _projectListItemAdded(
    dynamic currentValue,
    ListViewItemAdded change,
  ) {
    final list = currentValue as List<ListItem>;

    // Check for duplicate refId
    if (list.any((item) => item.refId == change.item)) {
      // Duplicate found, no change to apply
      return (list, null);
    }

    // Not a duplicate, assign position and add
    final pos = _nextListPosition();
    list.add(ListItem(pos, change.item));

    // Convert to query change
    final queryChange = QueryListViewItemAdded(pos: pos, refId: change.item);

    return (list, queryChange);
  }

  (List<ListItem>, Change?) _projectListItemRemoved(
    dynamic currentValue,
    ListViewItemRemoved change,
  ) {
    final list = currentValue as List<ListItem>;

    final removeAtIndex = list.indexWhere((i) => i.refId == change.item);
    if (removeAtIndex == -1) {
      // Item not found in list, nothing to remove
      return (list, null);
    }

    final removedItem = list.removeAt(removeAtIndex);

    // Convert to query change
    final queryChange = QueryListViewItemRemoved(
      pos: removedItem.position,
      refId: removedItem.refId,
    );

    return (list, queryChange);
  }

  @override
  Future<ListItem?> getNextListItem(
    String entityName,
    EntityId entityId,
    String viewName,
    double afterPos,
  ) async {
    final snapshot = await viewSnapshot(entityName, entityId, viewName);
    final items = snapshot.value as List<ListItem>;

    // To get the "right" neighbour - search in forward direction, from 0 to items.length.
    // Do not use "lastIndexWhere" - you'll always get the last item in the list.
    final nextIndex = items.indexWhere((i) => i.position > afterPos);

    if (nextIndex == -1) {
      return null;
    }

    return items[nextIndex];
  }

  @override
  Future<ListItem?> getPreviousListItem(
    String entityName,
    EntityId entityId,
    String viewName,
    double beforePos,
  ) async {
    final snapshot = await viewSnapshot(entityName, entityId, viewName);
    final items = snapshot.value as List<ListItem>;

    // To get the "left" neighbour - search in reverse, from items.length to 0.
    // Do not use "firstIndexWhere" - you'll always get the first item in the list.
    final previousIndex = items.lastIndexWhere((i) => i.position < beforePos);

    if (previousIndex == -1) {
      return null;
    }

    return items[previousIndex];
  }

  ListViewRange _getRangeFromRefListSnapshot(
    ViewSnapshot snap,
    String startAfter,
    String endBefore,
    int limit,
  ) {
    final list = snap.value as List<ListItem>;

    // Find start position and index (exclusive of startAfter)
    int startIndex = 0;
    double startAfterPos = 0.0;
    if (startAfter.isNotEmpty) {
      final afterIndex = list.indexWhere((item) => item.refId == startAfter);
      if (afterIndex != -1) {
        startIndex = afterIndex + 1;
        startAfterPos = list[afterIndex].position;
      }
    }

    // Find end position and index (exclusive of endBefore)
    int endIndex = list.length;
    double endBeforePos = 0.0;
    if (endBefore.isNotEmpty) {
      final beforeIndex = list.indexWhere((item) => item.refId == endBefore);
      if (beforeIndex != -1) {
        endIndex = beforeIndex;
        endBeforePos = list[beforeIndex].position;
      }
    }

    // Get the sublist within boundaries
    var result = list.sublist(startIndex, endIndex);

    // Apply limit
    final absLimit = limit.abs();
    if (result.length > absLimit) {
      if (limit > 0) {
        // Positive limit: take first N elements
        result = result.sublist(0, absLimit);
      } else {
        // Negative limit: take last N elements
        result = result.sublist(result.length - absLimit);
      }
    }

    return ListViewRange(
      items: result,
      startAfterPos: startAfterPos,
      endBeforePos: endBeforePos,
    );
  }

  ListViewPage _createListPage(
    ViewKey viewKey,
    double startAfter,
    double endBefore,
    int limit,
    List<ListItem> pageItems,
  ) {
    return ListViewPage(
      pageId: Xid().toString(),
      startAfter: startAfter,
      endBefore: endBefore,
      lo: pageItems.firstOrNull?.position ?? 0,
      hi: pageItems.lastOrNull?.position ?? 0,
      limit: limit,
      currentSize: pageItems.length,
      viewKey: viewKey,
      viewStore: this,
    );
  }

  void _throwIfInvalidPaginationParams(ListQueryDef def) {
    if (def.limit == 0) {
      throw ArgumentError.value(
        def.limit,
        'limit',
        'list view limit can not be 0',
      );
    }

    if (def.limit > 0 && def.endBefore.isNotEmpty) {
      throw ArgumentError(
        'endBefore can not be used with forward pagination',
      );
    }

    if (def.limit < 0 && def.startAfter.isNotEmpty) {
      throw ArgumentError(
        'startAfter can not be used with reverse pagination',
      );
    }
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
    view.entityId = '__default';
    defaultValues.addAll(
      view.initValues(),
    );
  }

  final views = <View>[];
  final defaultValues = <InitViewData>[];
}
