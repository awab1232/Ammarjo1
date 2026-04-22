import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firebase ID token + Authorization header provider.
abstract final class FirebaseAuthHeaderProvider {
  FirebaseAuthHeaderProvider._();

  static Future<String> requireIdToken({
    required String reason,
    bool forceRefresh = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH-HEADER] reason=$reason user=${user?.uid}');
    if (user == null) throw StateError('NULL_RESPONSE');
    final token = await user.getIdToken(forceRefresh);
    debugPrint('[AUTH-HEADER] reason=$reason token=$token');
    debugPrint('[AUTH-HEADER] reason=$reason token_is_null=${token == null}');
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) throw StateError('NULL_RESPONSE');
    return trimmed;
  }

  static Future<Map<String, String>> requireAuthHeaders({
    required String reason,
    bool forceRefresh = false,
  }) async {
    final token = await requireIdToken(reason: reason, forceRefresh: forceRefresh);
    return <String, String>{'Authorization': 'Bearer $token'};
  }

  static Future<Map<String, String>> authHeadersIfSignedIn({
    required String reason,
    bool forceRefresh = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH-HEADER] optional reason=$reason user=${user?.uid}');
    if (user == null) return <String, String>{};
    final token = await user.getIdToken(forceRefresh);
    debugPrint('[AUTH-HEADER] optional reason=$reason token=$token');
    debugPrint('[AUTH-HEADER] optional reason=$reason token_is_null=${token == null}');
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) return <String, String>{};
    return <String, String>{'Authorization': 'Bearer $trimmed'};
  }

  static void logRequestHeaders({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
  }) {
    debugPrint('[AUTH-HEADER] request $method $uri headers=$headers');
  }
}
