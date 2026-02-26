import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xid/xid.dart';

import 'system.dart';
import 'ws.dart';

class AuthEvent {
  AuthEvent({required this.eventType, required this.payload});

  final String eventType;
  final Map<String, dynamic> payload;
}

class HttpServer {
  HttpServer({required this.system});

  final HordaServerSystem system;

  final app = Router();

  final logger = Logger('Horda.HttpServer');

  void start() {
    app.get('/client', (Request request) async {
      final conInfo =
          request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final senderAddr = conInfo?.remoteAddress.address;

      String? userId;

      try {
        final authEvent = _extractAuthEvent(request.headers);

        if (authEvent != null) {
          userId = await system.runAuthProcess(authEvent);
        }
      } on AuthException catch (e) {
        // Status: 401
        return Response.unauthorized(
          e.toString(),
        );
      } catch (e) {
        // Status: 500
        return Response.internalServerError(
          body: e.toString(),
        );
      }

      final isIncognito = userId == null;
      logger.info(
        'Opening ${isIncognito ? 'incognito' : 'logged in'} connection for $senderAddr ...',
      );

      return webSocketHandler(
        pingInterval: Duration(seconds: 5),
        protocols: ['horda'],
        (WebSocketChannel channel) {
          var session = WsSession(
            sessionId: Xid().toString(),
            userId: userId,
            channel: channel,
            system: system,
          );

          session.start();
        },
      )(request);
    });

    final port = int.parse(Platform.environment['PORT'] ?? '8080');
    final ip = InternetAddress.anyIPv4;

    io.serve(app, ip, port).then((server) {
      logger.info('started at http://${server.address.host}:${server.port}');
    });
  }

  AuthEvent? _extractAuthEvent(Map<String, String> headers) {
    final protocolsHeader = headers['Sec-WebSocket-Protocol'];

    if (protocolsHeader == null) {
      return null;
    }

    final values = protocolsHeader.split(',');

    // Headers should be in the following order: horda, API_KEY, AUTH_EVENT_BASE64
    if (values.length < 3) {
      return null;
    }

    final authPayload = values[2].trim();

    if (authPayload.isEmpty) {
      return null;
    }

    try {
      final decoded = utf8.decode(
        base64Url.decode(
          base64Url.normalize(
            authPayload,
          ),
        ),
      );

      final json = jsonDecode(decoded) as Map<String, dynamic>;

      return AuthEvent(
        eventType: json['eventType'] as String,
        payload: json['payload'] as Map<String, dynamic>,
      );
    } catch (e) {
      logger.warning('Failed to decode auth event: $e');
      throw AuthException(
        e.toString(),
      );
    }
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() {
    return message;
  }
}
