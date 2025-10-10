import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xid/xid.dart';

import 'auth.dart';
import 'system.dart';
import 'ws.dart';

class HttpServer {
  HttpServer({required this.system});

  final HordaServerSystem system;

  final app = Router();

  final auth = Auth();

  final logger = Logger('Horda.HttpServer');

  void start() {
    app.get('/client', (Request request) async {
      final conInfo =
          request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      final senderAddr = conInfo?.remoteAddress.address;

      String? userId;

      try {
        userId = await processHeaders(request.headers);
      } on FormatException catch (e) {
        return Response(400, body: e.toString());
      } on JWTExpiredException {
        logger.warning(
          'Received expired JWT from $senderAddr, incognito connection will be opened.',
        );
      } on JWTException catch (e) {
        return Response(403, body: e.toString());
      } catch (e) {
        return Response(500, body: e.toString());
      }

      final isIncognito = userId == null;
      logger.info(
        'Opening ${isIncognito ? 'incognito' : 'logged in'} connection for $senderAddr ...',
      );

      return webSocketHandler(
        pingInterval: Duration(seconds: 5),
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

  /// Processes request headers and returns a userId or null. <br/>
  /// Throws [FormatException] in case of header format errors. <br/>
  Future<String?> processHeaders(Map<String, String> headers) async {
    if (headers['firebaseIdToken'] == null) {
      // Return null for incognito connection
      return null;
    }

    final idToken = headers['firebaseIdToken']!;
    final userId = await auth.extractUserId(idToken);

    return userId;
  }
}
