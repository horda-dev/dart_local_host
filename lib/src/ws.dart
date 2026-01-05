import 'dart:async';
import 'dart:collection';

import 'package:async/async.dart';
import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'list_page_manager.dart';
import 'log.dart';
import 'store.dart';
import 'system.dart';

final class WsSession {
  final String sessionId;

  final EntityId? userId;

  final WebSocketChannel channel;

  final Logger logger;

  final HordaServerSystem system;

  final pageManager = ListPageManager();

  String get id => '$sessionId:$userId';

  // Websocket input stream subscription (from client to server).
  StreamSubscription<dynamic>? _inputSub;

  set inputSub(StreamSubscription<dynamic>? value) {
    _inputSub?.cancel();
    _inputSub = value;
  }

  StreamSubscription<dynamic>? get inputSub => _inputSub;

  // Websocket output stream subscription (from server to client).
  StreamSubscription<WsMessageBox>? _outputSub;

  set outputSub(StreamSubscription<WsMessageBox>? value) {
    _outputSub?.cancel();
    _outputSub = value;
  }

  StreamSubscription<WsMessageBox>? get outputSub => _outputSub;

  WsSession({
    required this.sessionId,
    required this.userId,
    required this.channel,
    required this.system,
  }) : logger = Logger('Server.WsSession');

  void start() {
    logger.fine('$id starting...');

    _send(
      WsMessageBox(
        id: 0,
        msg: WelcomeWsMsg(userId, '1.0.0'),
      ),
    );

    inputSub = channel.stream.listen(
      _onMessage,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: true,
    );

    outputSub = _outStream.stream.listen(
      (box) => _send(box),
      onDone: () => logger.shout('out stream is done'),
      onError: (error) => logger.severe('out stream error $error'),
      cancelOnError: false,
    );

    logger.info('$id started');
  }

  void _onMessage(dynamic data) async {
    logger.fine('$id received ${limitString(data.toString())}');

    var box = WsMessageBox.decodeJson(data, logger);
    logger.info('$id decoded box ${limitString(box.toString())}');

    var msg = box.msg;
    var res = switch (msg) {
      QueryWsMsg() => await _onQuery(msg),
      QueryAndSubscribeWsMsg() => await _onQueryAndSubscribe(msg),
      SendCommandWsMsg() => await _onSendCommand(msg),
      CallCommandWsMsg() => await _onCallCommand(msg),
      DispatchEventWsMsg() => await _onDispatchEvent(msg),
      SubscribeViewsWsMsg() => await _onViewSubscribe(msg),
      UnsubscribeViewsWsMsg() => await _onViewUnsubscribe(msg),
      ErrorWsMsg() => box.msg,
      _ => ErrorWsMsg('UnknownWsMessage', 'unknown error for input $data'),
    };

    _send(
      WsMessageBox(id: box.id, msg: res),
    );

    logger.info('$id handled $box');
    logger.fine('$id handled $data');
  }

  Future<WsMessage> _onQuery(QueryWsMsg msg) async {
    logger.fine('running query on ${msg.actorId}...');

    try {
      var res = await system.viewStore.query(
        actorId: msg.actorId,
        // TODO: remove name from query method params
        name: '',
        query: msg.def,
      );

      logger.info('ran query on ${msg.actorId}');

      return QueryResultWsMsg(
        result: res,
      );
    } catch (e) {
      logger.warning('run query error: $e');

      return ErrorWsMsg('${e.runtimeType}', 'query on ${msg.actorId}: $e');
    }
  }

  Future<WsMessage> _onQueryAndSubscribe(QueryAndSubscribeWsMsg msg) async {
    logger.fine('query and subscribe on ${msg.actorId}...');

    try {
      // Execute query and get result, changeIDs, and pages
      final res = await system.viewStore.queryForSubscription(
        actorId: msg.actorId,
        name: '',
        query: msg.def,
      );

      // Add pages to page manager after successful query
      for (final page in res.pages) {
        pageManager.addPage(page);
      }

      // Subscribe to each view using changeID from flat map
      for (final entry in res.changeIDs.entries) {
        final viewKey = entry.key;
        final key = viewKey.toString();
        final changeId = entry.value;

        if (_viewSubs.containsKey(key)) {
          // Unlike in explicit subscribe - here we just ignore existing subs,
          // because in this case, client can not request subs explicitly.
          continue;
        }

        // Create subscription stream starting from changeId
        final stream = system
            .changes(
              entityName: viewKey.entityName,
              id: viewKey.entityId,
              name: viewKey.viewName,
              startAt: changeId,
            )
            .asyncMap(_processChangeEnvelope);

        final clientSub = _ClientSubscription(key, changeId, stream);
        _viewSubs[key] = clientSub;
        _outStream.add(stream);

        logger.fine('subscribed to $key from changeId $changeId');
      }

      logger.info('query and subscribe completed for ${msg.actorId}');

      return QueryResultWsMsg(
        result: res.queryResult,
      );
    } catch (e) {
      logger.warning('query and subscribe error: $e');
      return ErrorWsMsg(
        '${e.runtimeType}',
        'query and subscribe on ${msg.actorId}: $e',
      );
    }
  }

  Future<WsMessage> _onSendCommand(SendCommandWsMsg msg) async {
    logger.fine(
      'user ${userId ?? 'Incognito'} sending command ${msg.type} to ${msg.to}...',
    );

    try {
      system.sendEntityJson(
        msg.actorName,
        msg.to,
        userId ?? '',
        msg.type,
        msg.cmd,
      );

      logger.info('sent ${msg.type} to ${msg.to}');

      return SendCommandAckWsMsg();
    } catch (e) {
      logger.warning('send ${msg.type} to ${msg.to} failed with $e');

      return ErrorWsMsg(
        '${e.runtimeType}',
        'send ${msg.type} to ${msg.to}: $e',
      );
    }
  }

  Future<WsMessage> _onCallCommand(CallCommandWsMsg msg) async {
    logger.fine(
      'user ${userId ?? 'Incognito'} calling command from ${msg.type} to ${msg.to}...',
    );

    try {
      final commandId = system.sendEntityJson(
        msg.actorName,
        msg.to,
        userId ?? '',
        msg.type,
        msg.cmd,
      );

      final envelop = await system.entityEvents(commandId: commandId).first;

      logger.info('call ${msg.type} to ${msg.to} ok with $envelop');

      return CallCommandResWsMsg(
        true,
        {'eventType': envelop.type, 'event': envelop.event},
      );
    } catch (e) {
      logger.warning('call ${msg.type} to ${msg.to} failed with $e');

      return ErrorWsMsg(
        '${e.runtimeType}',
        'call ${msg.type} to ${msg.to}: $e',
      );
    }
  }

  Future<WsMessage> _onDispatchEvent(DispatchEventWsMsg msg) async {
    logger.fine(
      'user ${userId ?? 'Incognito'} dispatching event ${msg.type}',
    );

    try {
      final result = await system.dispatchEventJson(
        userId ?? '',
        msg.type,
        msg.event,
      );

      logger.info('dispatched ${msg.type} from $userId with $result');

      return DispatchEventResWsMsg(result);
    } catch (e) {
      logger.warning('dispatch ${msg.type} from $userId failed with $e');

      return ErrorWsMsg(
        '${e.runtimeType}',
        'dispatch ${msg.type} from $userId: $e',
      );
    }
  }

  Future<WsMessage> _onViewSubscribe(SubscribeViewsWsMsg msg) async {
    logger.fine('subscribing to ${msg.subs.length} views...');

    for (final sub in msg.subs) {
      final key = sub.viewKey;

      if (_viewSubs.containsKey(key)) {
        logger.warning('duplicate subscription request for $key');
        continue;
      }

      // Start from beginning for simple subscribe (no query snapshot available)
      final changeId = '';

      final stream = system
          .changes(
            entityName: sub.entityName,
            id: sub.id,
            name: sub.name,
            startAt: changeId,
          )
          .asyncMap(_processChangeEnvelope);

      final clientSub = _ClientSubscription(key, changeId, stream);

      _viewSubs[key] = clientSub;

      _outStream.add(stream);

      logger.fine('subscribed to $key');
    }

    logger.info('subscribed');

    return SubscribeViewsAckWsMsg();
  }

  Future<WsMessage> _onViewUnsubscribe(UnsubscribeViewsWsMsg msg) async {
    logger.fine('unsubscribing from ${msg.subs.length} views...');

    for (var sub in msg.subs) {
      if (sub.pageId != null) {
        _unsubscribeFromListView(sub);
      } else {
        _unsubscribeFromView(sub);
      }
    }

    logger.info('unsubscribed');
    return UnsubscribeViewsResWsMsg();
  }

  void _unsubscribeFromListView(ActorViewSub sub) {
    // Remove page from page manager
    pageManager.removePage(sub.pageId!);

    // Check if any other pages exist for this view
    final viewKey = ViewKey(sub.entityName, sub.id, sub.name);
    final hasOtherPages = pageManager.hasPagesForView(viewKey);

    if (hasOtherPages) {
      logger.fine('removed page ${sub.pageId} from $sub (other pages remain)');
      return;
    }

    // No pages remain, unsubscribe from view stream
    final key = sub.viewKey; // Use viewKey (without pageId)
    if (_viewSubs.containsKey(key)) {
      final activeSub = _viewSubs[key]!;
      _outStream.remove(activeSub.stream);
      _viewSubs.remove(key);
      logger.fine('unsubscribed from list view $sub (no pages remain)');
    }
  }

  void _unsubscribeFromView(ActorViewSub sub) {
    final key = sub.viewKey;

    if (!_viewSubs.containsKey(key)) {
      logger.warning('no subscription found for $key');
      return;
    }

    final activeSub = _viewSubs[key]!;
    _outStream.remove(activeSub.stream);
    _viewSubs.remove(key);
    logger.fine('unsubscribed from $sub');
  }

  void _onError(dynamic error) {
    print('$id error $error');
    logger.warning('$id error $error');
  }

  /// When client closes/looses connection a "done" event will be emitted to
  /// the websocket channel stream.
  ///
  /// So this is the place where all session resources should be disposed.
  void _onDone() {
    logger.info('$id stopping...');

    // Dispose all subscriptions.
    for (final sub in _viewSubs.values) {
      _outStream.remove(sub.stream);
    }
    _viewSubs.clear();

    // Close the output stream.
    _outStream.close();

    // Cancel input and output websocket stream subscriptions.
    inputSub?.cancel();
    outputSub?.cancel();

    // These should be GC'd, but remove them anyway, for consistency.
    pageManager.removeAllPages();

    logger.info('$id stopped');
  }

  void _send(WsMessageBox box) {
    logger.fine('$id sending $box...');

    var json = box.encodeJson(logger);
    channel.sink.add(json);

    logger.info('$id sent box: $box');
    logger.fine('$id sent json: $json');
  }

  /// Processes a change envelope through the page manager before sending to client.
  ///
  /// This is the single entry point for all change envelopes flowing to the client.
  /// It runs the envelope through the page manager to convert list-level changes
  /// into page-specific sync changes.
  Future<WsMessageBox> _processChangeEnvelope(ChangeEnvelop env) async {
    var processedEnv = env;

    final viewKey = ViewKey(env.entityName, env.key, env.name);
    print('Processing: $viewKey');

    // Run through page manager to get page sync changes
    if (pageManager.hasPagesForView(viewKey)) {
      print('Has page: $viewKey');

      processedEnv = await pageManager.handleChangeEnvelope(env);
    }

    // Wrap in message box
    return WsMessageBox(
      id: 0,
      msg: ViewChangeWsMsg(processedEnv),
    );
  }

  final _outStream = StreamGroup<WsMessageBox>.broadcast();
  final _viewSubs = HashMap<String, _ClientSubscription>();
}

class _ClientSubscription {
  _ClientSubscription(
    this.key,
    this.changeId,
    this.stream,
  );

  final String key;

  final String changeId;

  final Stream<WsMessageBox> stream;

  @override
  int get hashCode => key.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is _ClientSubscription) {
      return key == other.key;
    }

    return false;
  }

  @override
  String toString() {
    return 'Sub(key: $key, chid: $changeId)';
  }
}
