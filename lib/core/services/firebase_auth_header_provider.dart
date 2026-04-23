import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../session/user_session.dart';

/// Centralized Firebase ID token + `Authorization: Bearer <idToken>` for REST calls to NestJS.
/// Token is obtained with [User.getIdToken] (force refresh) and attached as the sole auth mechanism.
abstract final class FirebaseAuthHeaderProvider {
  FirebaseAuthHeaderProvider._();

  static Future<String> requireIdToken({
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH-HEADER] reason=$reason user=${user?.uid}');
    if (user == null) {
      final token = UserSession.authToken?.trim() ?? '';
      if (token.isEmpty) throw StateError('NULL_RESPONSE');
      return token;
    }
    final token = await user.getIdToken(true);
    debugPrint('[AUTH-HEADER] reason=$reason token_is_null=${token == null} len=${token?.trim().length ?? 0}');
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) throw StateError('NULL_RESPONSE');
    if (kDebugMode) {
      // ignore: avoid_print
      print('🔥 FIREBASE TOKEN: $trimmed');
    }
    return trimmed;
  }

  static Future<Map<String, String>> requireAuthHeaders({
    required String reason,
  }) async {
    final token = await requireIdToken(reason: reason);
    // Match backend: Bearer = Firebase **ID** token (not session cookie). Add
    // `Content-Type: application/json` on POST/PATCH/PUT in the caller when sending a body.
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  static Future<Map<String, String>> authHeadersIfSignedIn({
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH-HEADER] optional reason=$reason user=${user?.uid}');
    if (user == null) {
      final token = UserSession.authToken?.trim() ?? '';
      if (token.isEmpty) return <String, String>{};
      return <String, String>{'Authorization': 'Bearer $token'};
    }
    final token = await user.getIdToken(true);
    debugPrint('[AUTH-HEADER] optional reason=$reason token_is_null=${token == null} len=${token?.trim().length ?? 0}');
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) return <String, String>{};
    if (kDebugMode) {
      // ignore: avoid_print
      print('🔥 FIREBASE TOKEN: $trimmed');
    }
    return <String, String>{'Authorization': 'Bearer $trimmed'};
  }

  static void logRequestHeaders({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
  }) {
    debugPrint('[AUTH-HEADER] request $method $uri headers=$headers');
    if (kDebugMode) {
      final hasAuth = (headers['Authorization'] ?? '').trim().isNotEmpty;
      // ignore: avoid_print
      print('🔥 REQUEST: $method $uri  (Authorization: ${hasAuth ? 'Bearer <${headers['Authorization']?.length} chars>' : 'MISSING'})');
    }
  }

  /// One-line log for debugging HTTP responses (kDebug only; long bodies are truncated).
  static void logDebugResponse(String context, int status, String body, {int maxBodyLength = 16000}) {
    if (!kDebugMode) return;
    final b = body.length > maxBodyLength
        ? '${body.substring(0, maxBodyLength)}…(truncated, totalLen=${body.length})'
        : body;
    // ignore: avoid_print
    print('🔥 RESPONSE ($context) [$status]: $b');
  }
}
