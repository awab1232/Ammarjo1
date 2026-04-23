import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';
import '../utils/jordan_phone.dart';
import 'firebase_backend_session_service.dart';

/// Thrown by [PhonePasswordAuthService] with a user-friendly Arabic message
/// so callers can `catch` and surface it directly.
class PhonePasswordAuthException implements Exception {
  const PhonePasswordAuthException(this.code, this.messageAr);

  final String code;
  final String messageAr;

  @override
  String toString() => 'PhonePasswordAuthException($code): $messageAr';
}

class PhonePasswordAuthService {
  const PhonePasswordAuthService._();
  static String? _lastRole;
  static String? _lastUserId;

  static String? get lastRole => _lastRole;
  static String? get lastUserId => _lastUserId;

  static Uri _authUri(String path) {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      throw const PhonePasswordAuthException('backend_missing', 'رابط الخادم غير مضبوط.');
    }
    return Uri.parse('$base$path');
  }

  /// Registration after OTP verification: sends Firebase ID token + phone + password to backend.
  static Future<void> registerAfterOtp({
    required User firebaseUser,
    required String phone,
    required String password,
  }) async {
    final firebaseToken = await firebaseUser.getIdToken(true);
    if (firebaseToken == null || firebaseToken.trim().isEmpty) {
      throw const PhonePasswordAuthException('missing_firebase_token', 'تعذر استخراج رمز التحقق من Firebase.');
    }
    final normalized = normalizeJordanPhoneForUsername(phone);
    final uri = _authUri('/auth/register');
    final body = <String, dynamic>{
      'firebaseToken': firebaseToken.trim(),
      'phone': normalized,
      'password': password,
    };
    // ignore: avoid_print
    print('🔥 CALLING /auth/register');
    // ignore: avoid_print
    print('🔥 phone: $normalized');
    // ignore: avoid_print
    print('🔥 REGISTER REQUEST BODY: $body');
    final res = await http
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer ${firebaseToken.trim()}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    // ignore: avoid_print
    print('🔥 REGISTER RESPONSE: ${res.statusCode} ${res.body}');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const PhonePasswordAuthException('register_failed', 'تعذر تسجيل الحساب على الخادم.');
    }
    try {
      await FirebaseBackendSessionService.syncWithBackend(firebaseUser: firebaseUser);
    } on Object {
      // best effort
    }
  }

  /// Sign in with phone+password via backend `/auth/login` (not Firebase email/password).
  static Future<UserCredential> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    final normalized = normalizeJordanPhoneForUsername(phone);
    if (normalized.isEmpty) {
      throw const PhonePasswordAuthException('invalid_phone', 'رقم الهاتف غير صالح');
    }
    final uri = _authUri('/auth/login');
    final body = <String, dynamic>{'phone': normalized, 'password': password};
    // ignore: avoid_print
    print('🔥 FLUTTER LOGIN CALL: $uri body=$body');
    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    // ignore: avoid_print
    print('🔥 FLUTTER LOGIN RESPONSE: ${res.statusCode} ${res.body}');
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const PhonePasswordAuthException('invalid_credentials', 'رقم الهاتف أو كلمة المرور غير صحيحة');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw const PhonePasswordAuthException('bad_login_payload', 'استجابة تسجيل الدخول غير صالحة.');
    }
    final m = Map<String, dynamic>.from(decoded);
    final customToken = (m['customToken'] ?? '').toString().trim();
    final role = (m['role'] ?? '').toString().trim().toLowerCase();
    final userId = (m['userId'] ?? '').toString().trim();
    _lastRole = role.isNotEmpty ? role : null;
    _lastUserId = userId.isNotEmpty ? userId : null;
    // ignore: avoid_print
    print('🔥 USER ROLE: ${_lastRole ?? 'customer'}');
    if (customToken.isEmpty) {
      throw const PhonePasswordAuthException('missing_custom_token', 'تعذر إكمال جلسة تسجيل الدخول.');
    }
    UserCredential credential;
    try {
      credential = await FirebaseAuth.instance.signInWithCustomToken(customToken);
      // ignore: avoid_print
      print('🔥 USER SIGNED IN');
      await FirebaseBackendSessionService.syncWithBackend(firebaseUser: credential.user);
      // ignore: avoid_print
      print('🔥 BACKEND SYNC CALLED');
      debugPrint('[AUTH-AUDIT] login backend sync success for uid=${credential.user?.uid}');
      return credential;
    } on FirebaseBackendSessionException catch (e, st) {
      debugPrint('[AUTH-AUDIT] login backend sync failed: $e\n$st');
      await FirebaseAuth.instance.signOut();
      throw PhonePasswordAuthException(
        'backend_unavailable',
        e.message.isNotEmpty
            ? e.message
            : 'تم تسجيل الدخول في Firebase لكن تعذر ربط الجلسة مع الخادم',
      );
    } on StateError catch (e, st) {
      debugPrint('[AUTH-AUDIT] login id-token/backend glue failed: $e\n$st');
      await FirebaseAuth.instance.signOut();
      throw const PhonePasswordAuthException(
        'backend_unavailable',
        'تم تسجيل الدخول في Firebase لكن تعذر ربط الجلسة مع الخادم',
      );
    } on Object catch (e, st) {
      debugPrint('[AUTH-AUDIT] login backend sync unexpected: $e\n$st');
      await FirebaseAuth.instance.signOut();
      throw const PhonePasswordAuthException(
        'backend_unavailable',
        'تم تسجيل الدخول في Firebase لكن تعذر ربط الجلسة مع الخادم',
      );
    }
  }
}
