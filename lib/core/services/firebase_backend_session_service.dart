import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';
import 'firebase_auth_header_provider.dart';

class FirebaseBackendSessionException implements Exception {
  const FirebaseBackendSessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class FirebaseBackendSessionService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _kBackendLoggedIn = 'backend_logged_in';

  static Future<Map<String, dynamic>> syncWithBackend({
    User? firebaseUser,
  }) async {
    // ignore: avoid_print
    print('🔥 CALLING BACKEND SYNC');
    final user = firebaseUser ?? FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH-AUDIT] Firebase user: ${user?.uid}');
    if (user == null) {
      throw const FirebaseBackendSessionException('No Firebase user session.');
    }
    final idToken = await FirebaseAuthHeaderProvider.requireIdToken(reason: 'firebase_backend_sync');
    debugPrint('[AUTH-AUDIT] ID Token length: ${idToken.length}');
    if (idToken.isEmpty) {
      throw const FirebaseBackendSessionException('Missing Firebase ID token.');
    }
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      throw const FirebaseBackendSessionException('Backend base URL missing.');
    }
    final uri = Uri.parse('$base/auth/firebase-login');
    // ignore: avoid_print
    print('🔥 INSIDE SYNC');
    // ignore: avoid_print
    print('🔥 TOKEN: $idToken');
    // ignore: avoid_print
    print('🔥 REQUEST: POST $uri');
    final res = await http
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 20));
    // ignore: avoid_print
    print('🔥 HTTP POST EXECUTED status=${res.statusCode} bodyLen=${res.body.length}');
    debugPrint('[AUTH-AUDIT] Backend status: ${res.statusCode}');
    debugPrint('[AUTH-AUDIT] Backend body: ${res.body}');
    FirebaseAuthHeaderProvider.logDebugResponse('POST /auth/firebase-login', res.statusCode, res.body);

    final decoded = _safeDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300 || decoded == null) {
      throw FirebaseBackendSessionException('Backend auth failed (${res.statusCode}).');
    }

    await _storage.write(key: _kBackendLoggedIn, value: 'true');
    debugPrint('[AUTH-AUDIT] logged_in flag saved=true');
    return decoded;
  }

  static Future<bool> restoreAndSyncIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await clear();
      return false;
    }
    final loggedIn = await _storage.read(key: _kBackendLoggedIn);
    debugPrint('[AUTH-AUDIT] restore logged_in=$loggedIn');
    if (loggedIn == 'true') {
      await syncWithBackend(firebaseUser: user);
      return true;
    }
    return false;
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kBackendLoggedIn);
    debugPrint('[AUTH-AUDIT] secure session cleared');
  }

  static Map<String, dynamic>? _safeDecode(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }
}
