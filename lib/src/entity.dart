import 'dart:async';
import 'dart:collection';

import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';

import 'change_id.dart';
import 'system.dart';

class EntityHost<S extends EntityState> {
  EntityHost(
    this._entityId,
    this.entity,
    this.viewGroup,
    this._system,
  ) : logger = Logger('Horda.Entity.${entity.runtimeType}') {
    logger.fine('id: $_entityId starting...');

    // Check if this is a singleton entity first
    final singletonState = entity.singleton;
    _isSingleton = singletonState != null;

    _handlers = _EntityHandlers<S>(entity.name, this, logger, _isSingleton);
    entity.initHandlers(_handlers);

    _viewGroupProjectors = _ViewGroupProjectors(
      _entityId,
      entity.name,
      viewGroup,
      _system.changeIdTracker,
      _isSingleton,
    );

    if (_isSingleton) {
      // Singleton entities must use the constant ID 'singleton'
      if (_entityId != kSingletonId) {
        throw HordaLocalHostError(
          'Singleton entity ${entity.name} must be addressed by the constant ID "$kSingletonId". '
          'Expected ID: "$kSingletonId", but got: "$_entityId". '
          'Only one singleton entity can exist in the system.',
        );
      }
      _state = singletonState;
      _initSingletonViews();
      logger.fine('id: $_entityId detected singleton, initializing immediately');
    }

    _sub = _system
        .entityCommands(
          entity.name,
          _entityId,
        )
        .listen(_handleCommand);

    logger.info('id: $_entityId started');
  }

  final Entity<S> entity;

  final EntityViewGroup viewGroup;

  final Logger logger;

  late final bool _isSingleton;

  void stop() {
    if (_isSingleton) {
      throw HordaLocalHostError(
        'Cannot stop singleton entity ${entity.name}. '
        'Singleton entities are pre-initialized at system startup and cannot be stopped.',
      );
    }

    logger.fine('id: $_entityId stopping...');

    _sub.cancel();
    _inbox.clear();

    logger.info('id: $_entityId stopped');
  }

  Future<QueryResult> query(EntityId entityId, QueryDef query) {
    return _system.viewStore.query(
      actorId: entityId,
      name: '',
      query: query,
    );
  }

  /// Initializes views for singleton entities using default values.
  Future<void> _initSingletonViews() async {
    logger.fine('id: $_entityId initializing singleton views...');

    final defaultViewData = _viewGroupProjectors.getDefaultViewData();

    await _system.viewStore.initEntityViews(
      entity.name,
      _entityId,
      defaultViewData,
    );

    logger.info('id: $_entityId initialized singleton with default views');
  }

  void _handleCommand(CommandEnvelop env) {
    if (!_idle) {
      _inbox.add(env);
      return;
    }

    _loop(env);
  }

  void _loop(CommandEnvelop env) async {
    _idle = false;
    _inbox.add(env);

    do {
      final next = _inbox.removeFirst();

      try {
        logger.fine('id: $_entityId processing $env...');

        if (_state == null) {
          await _handleInit(next);
        } else {
          await _handle(next, _state!);
        }

        logger.info('id: $_entityId processed $env');
      } catch (e) {
        logger.severe('id: $_entityId processed $env with error: $e');

        final errorEvent = FluirErrorEvent(e.toString());

        _system.publishEntityEvent(
          EventEnvelop(
            actorId: _entityId,
            // Make eventId == commandId for easier matching when debugging.
            eventId: env.commandId,
            commandId: env.commandId,
            type: errorEvent.runtimeType.toString(),
            event: errorEvent.toJson(),
          ),
        );
      }
    } while (_inbox.isNotEmpty);
    _idle = true;
  }

  Future<void> _handleInit(CommandEnvelop env) async {
    final (event, state) = await _handlers.handleInit(env);

    _state = state;

    final views = _viewGroupProjectors.projectInit(event);

    await _system.viewStore.initEntityViews(entity.name, _entityId, views);
    _system.publishEntityEvent(
      EventEnvelop(
        actorId: _entityId,
        // Make eventId == commandId for easier matching when debugging.
        eventId: env.commandId,
        commandId: env.commandId,
        type: event.runtimeType.toString(),
        event: event.toJson(),
      ),
    );
  }

  Future<void> _handle(CommandEnvelop env, S state) async {
    final event = await _handlers.handle(env, state);
    state.project(event);

    final changes = _viewGroupProjectors.project(event);

    _system.publishEntityEvent(
      EventEnvelop(
        actorId: _entityId,
        // Make eventId == commandId for easier matching when debugging.
        eventId: env.commandId,
        commandId: env.commandId,
        type: event.runtimeType.toString(),
        event: event.toJson(),
      ),
    );

    _system.publishManyChanges(changes);
  }

  final HordaServerSystem _system;

  final EntityId _entityId;
  S? _state;

  final _inbox = Queue<CommandEnvelop>();
  var _idle = true;

  late final _EntityHandlers<S> _handlers;
  late _ViewGroupProjectors _viewGroupProjectors;
  late final StreamSubscription<CommandEnvelop> _sub;
}

class _EntityHandlers<S extends EntityState> implements EntityHandlers<S> {
  _EntityHandlers(this.entityName, this.host, this.logger, this.isSingleton);

  final EntityHost host;

  final String entityName;

  final Logger logger;

  final bool isSingleton;

  @override
  void addInit<C extends RemoteCommand, E extends RemoteEvent>(
    EntityInitHandler<C, E> handler,
    FromJsonFun<C> cmdFromJson,
    EntityStateInitProjector<E> stateInit,
  ) {
    if (isSingleton) {
      throw HordaLocalHostError(
        'Singleton entity $entityName cannot add init handlers. '
        'Singleton entities are pre-initialized using the Entity.singleton getter '
        'and do not support initialization commands.',
      );
    }

    logger.fine('Adding init handler for $C');

    _entityInitHandler[C] = handler;
    _commandFactories[C.toString()] = cmdFromJson;
    _stateInitProjector[E] = stateInit;
  }

  @override
  void add<C extends RemoteCommand>(
    EntityHandler<S, C> handler,
    FromJsonFun<C> fromJson,
  ) {
    logger.fine('Adding handler for $C');

    _entityHandlers[C] = handler;
    _commandFactories[C.toString()] = fromJson;
  }

  @override
  void addStateFromJson(FromJsonFun<S> fromJson) {
    // Local host keeps state in memory, so there's no need to deserialize it.
    //
    // This method must do nothing.
  }

  Future<(RemoteEvent, S)> handleInit(CommandEnvelop env) async {
    logger.info(
      'Handling init command ${env.type} from ${env.from} to ${env.to}',
    );

    final context = _EntityContext(env.to, env.from, host);

    final cmd = _commandFromJson(env.type, env.command);
    final handler = _entityInitHandler[cmd.runtimeType];

    if (handler == null) {
      throw HordaLocalHostError(
        'entity $entityName has no handler registered for init command type: ${cmd.runtimeType}',
      );
    }

    final event = await handler(cmd, context);

    final stateInitProjector = _stateInitProjector[event.runtimeType];
    if (stateInitProjector == null) {
      throw HordaLocalHostError(
        'entity $entityName state $S has no init projector registered for type: ${event.runtimeType}',
      );
    }

    final state = stateInitProjector(event);

    return (event, state) as (RemoteEvent, S);
  }

  Future<RemoteEvent> handle(
    CommandEnvelop env,
    S state,
  ) async {
    logger.info(
      'Handling command ${env.type} from ${env.from} to ${env.to}',
    );

    final context = _EntityContext(env.to, env.from, host);

    final cmd = _commandFromJson(env.type, env.command);
    final handler = _entityHandlers[cmd.runtimeType];

    if (handler == null) {
      throw HordaLocalHostError(
        'entity $entityName has no handler registered for command type: ${cmd.runtimeType}',
      );
    }

    final event = await handler(cmd, state, context);

    return event as RemoteEvent;
  }

  RemoteCommand _commandFromJson(String type, Map<String, dynamic> json) {
    final fac = _commandFactories[type];
    if (fac == null) {
      throw HordaLocalHostError(
        'entity $entityName has no json factory registered for command type: $type',
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

  final _entityHandlers = <Type, dynamic>{};
  final _entityInitHandler = <Type, dynamic>{};
  final _stateInitProjector = <Type, dynamic>{};
  final _commandFactories = <String, dynamic>{};
}

class _EntityContext implements EntityContext {
  _EntityContext(this.entityId, this.senderId, this.host);

  final EntityHost host;

  @override
  final EntityId entityId;

  @override
  final EntityId senderId;

  @override
  DateTime get clock => DateTime.now().toUtc();

  @override
  Future<QueryResult> query(EntityId entityId, QueryDef query) {
    return host.query(entityId, query);
  }

  @override
  void stop() {
    host.stop();
    host._system.removeEntity(host.entity.name, entityId);
  }

  // Not exposed in EntityContext API yet.
  Logger get logger => host.logger;
}

class _ViewGroupProjectors implements EntityViewGroupProjectors {
  _ViewGroupProjectors(
    this.entityId,
    this.entityName,
    this.viewGroupDef,
    this.changeIdTracker,
    this.isSingleton,
  ) : _views = _ViewGroup(entityId, entityName, changeIdTracker) {
    viewGroupDef.initProjectors(this);
    viewGroupDef.initViews(_views);
  }

  final String entityId;
  final String entityName;

  final EntityViewGroup viewGroupDef;
  final ChangeIdTracker changeIdTracker;
  final bool isSingleton;

  @override
  void addInit<E extends RemoteEvent>(EntityViewGroupInit<E> projector) {
    if (isSingleton) {
      throw HordaLocalHostError(
        'Singleton entity view group for $entityName cannot add init projectors. '
        'Singleton entities use default view values instead of event-based initialization.',
      );
    }

    _initProjector[E] = projector;
  }

  @override
  void add<E extends RemoteEvent>(EntityViewGroupProjector<E> projector) {
    _projectors[E] = projector;
  }

  /// Returns default view data for singleton entities.
  /// Uses the viewGroup's default values instead of event-based initialization.
  List<InitViewData> getDefaultViewData() {
    final views = _ViewGroup(entityId, entityName, changeIdTracker);
    viewGroupDef.initViews(views);
    views.setEntityId(entityId);
    return views.initValues().toList();
  }

  List<InitViewData> projectInit(RemoteEvent event) {
    final init = _initProjector[event.runtimeType];
    if (init == null) {
      throw HordaLocalHostError(
        'entity $entityName view group has no init projector registered for event: ${event.runtimeType}',
      );
    }

    final viewGroupDef = init(event) as EntityViewGroup;
    final views = _ViewGroup(entityId, entityName, changeIdTracker);
    viewGroupDef.initViews(views);
    views.setEntityId(entityId);

    return views.initValues().toList();
  }

  List<ChangeEnvelop> project(RemoteEvent event) {
    final projector = _projectors[event.runtimeType];
    if (projector == null) {
      return [];
    }

    _views.setEntityId(entityId);

    // Each projector is a method of the EntityViewGroup instance assigned to viewGroupDef.
    // _views contain views, which are members of the viewGroupDef.
    // Essentially we are mutating views, which are members of that specific instance assigned to viewGroupDef.
    projector(event);

    return _views.changes().toList();
  }

  final _initProjector = <Type, dynamic>{};
  final _projectors = <Type, dynamic>{};
  final _ViewGroup _views;
}

class _ViewGroup implements ViewGroup {
  _ViewGroup(this.entityId, this.entityName, this.changeIdTracker);

  final String entityId;
  final String entityName;
  final ChangeIdTracker changeIdTracker;

  @override
  void add(View view) {
    _views.add(view);
    view.entityId = entityId;
  }

  void setEntityId(String entityId) {
    for (var view in _views) {
      view.entityId = entityId;
    }
  }

  Iterable<InitViewData> initValues() {
    return _views.expand((v) => v.initValues());
  }

  Iterable<ChangeEnvelop> changes() {
    return _views.expand((v) => _packChanges(v, v.changes()));
  }

  Iterable<ChangeEnvelop> _packChanges(View v, Iterable<Change> changes) {
    if (v is RefView || v is RefListView) {
      final viewChanges = <Change>[];
      final attrChanges = <RefIdNamePair, List<Change>>{};
      for (final change in changes) {
        if (change is AttributeChange) {
          attrChanges.update(
            (itemId: change.attrId, name: change.attrName),
            (value) => [...value, change],
            ifAbsent: () => [change],
          );
          continue;
        }
        viewChanges.add(change);
      }

      return [
        // View changes
        if (viewChanges.isNotEmpty)
          ChangeEnvelop(
            changeId: changeIdTracker
                .incrementForView(
                  entityName: entityName,
                  entityId: v.entityId!,
                  viewName: v.name,
                )
                .toString(),
            entityName: entityName,
            key: v.entityId!,
            name: v.name,
            changes: viewChanges,
          ),
        // Attr changes
        for (final MapEntry(:key, value: attrChanges) in attrChanges.entries)
          if (attrChanges.isNotEmpty)
            ChangeEnvelop(
              changeId: changeIdTracker
                  .incrementForAttribute(
                    entityId1: v.entityId!,
                    entityId2: key.itemId,
                    attrName: key.name,
                  )
                  .toString(),
              // Entity name is empty for attribute changes
              entityName: '',
              key: CompositeId(v.entityId!, key.itemId).id,
              name: key.name,
              changes: attrChanges,
            ),
      ];
    }

    // If ValueView, CounterView
    return [
      if (changes.isNotEmpty)
        ChangeEnvelop(
          changeId: changeIdTracker
              .incrementForView(
                entityName: entityName,
                entityId: v.entityId!,
                viewName: v.name,
              )
              .toString(),
          entityName: entityName,
          key: v.entityId!,
          name: v.name,
          changes: [...changes],
        ),
    ];
  }

  final _views = <View>[];
}

class EntityHandleResult {
  // final
}

extension CompactMap<E> on Iterable<E> {
  Iterable<T> compactMap<T>(T? Function(E) f) {
    return map(f).where((e) => e != null).cast();
  }
}
