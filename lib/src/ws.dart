import 'dart:collection';

import 'package:async/async.dart';
import 'package:horda_server/horda_server.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'log.dart';
import 'system.dart';

final class WsSession {
  final String sessionId;

  final EntityId? userId;

  final WebSocketChannel channel;

  final Logger logger;

  final HordaServerSystem system;

  String get id => '$sessionId:$userId';

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

    channel.stream.listen(
      _onMessage,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: true,
    );

    _outStream.stream.listen(
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
          '${e.runtimeType}', 'send ${msg.type} to ${msg.to}: $e');
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
      final key = sub.subKey;

      if (_viewSubs.containsKey(key)) {
        logger.warning('duplicate subscription request for $key');
        continue;
      }

      final changeId = sub.changeId;

      final stream = system
          .changes(
            entityName: sub.entityName,
            id: sub.id,
            name: sub.name,
            startAt: changeId,
          )
          .map(
            (env) => WsMessageBox(id: 0, msg: ViewChangeWsMsg(env)),
          );

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
      var key = sub.subKey;

      if (!_viewSubs.containsKey(key)) {
        logger.warning('no subscription found for $key');
        continue;
      }

      var activeSub = _viewSubs[key]!;
      _outStream.remove(activeSub.stream);
      _viewSubs.remove(key);

      logger.fine('unsubscribed from $sub');
    }

    logger.info('unsubscribed');
    return UnsubscribeViewsResWsMsg();
  }

  void _onError(dynamic error) {
    logger.warning('$id error $error');
  }

  void _onDone() {
    logger.info('$id stopped');
  }

  void _send(WsMessageBox box) {
    logger.fine('$id sending $box...');

    var json = box.encodeJson(logger);
    channel.sink.add(json);

    logger.info('$id sent box: $box');
    logger.fine('$id sent json: $json');
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
