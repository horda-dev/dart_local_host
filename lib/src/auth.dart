import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:logging/logging.dart';

class Auth {
  factory Auth() => _instance;
  Auth._();
  static final _instance = Auth._();

  final logger = Logger('Auth');

  /// Decodes JWT token without verification and extracts a userId from it.
  ///
  /// If JWT has format errors, throws a [FormatException].
  Future<String> extractUserId(String token) async {
    try {
      final jwt = JWT.decode(token);

      final sub = jwt.payload['sub'] as String?;

      if (sub == null) {
        throw FormatException('JWT payload has no \'sub\'.');
      }

      return sub;
    } catch (e) {
      logger.warning('Internal error: $e');
      rethrow;
    }
  }
}
