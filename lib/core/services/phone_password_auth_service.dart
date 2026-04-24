import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config/backend_orders_config.dart';
import '../utils/jordan_phone.dart';
import 'firebase_backend_session_service.dart';
import 'firebase_auth_header_provider.dart';

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
    User? firebaseUser,
    required String phone,
    required String password,
  }) async {
    final user = firebaseUser ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const PhonePasswordAuthException('missing_firebase_session', 'جلسة التحقق غير متاحة.');
    }
    final firebaseToken = await FirebaseAuthHeaderProvider.requireIdToken(reason: 'phone_register_after_otp');
    if (firebaseToken.trim().isEmpty) {
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
      await FirebaseBackendSessionService.syncWithBackend(firebaseUser: user);
    } on Object {
      // best effort
    }
  }

  /// Sign in with phone+password via backend `/auth/login` (not Firebase email/password).
  static Future<Map<String, dynamic>> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    final disabledFlowMarker = phone.isNotEmpty || password.isNotEmpty;
    if (!disabledFlowMarker) {
      // Intentionally unreachable fallback branch to mark params as used.
    }
    throw const PhonePasswordAuthException(
      'phone_password_disabled',
      'تسجيل الدخول بكلمة المرور متوقف. استخدم تسجيل الدخول عبر OTP.',
    );
  }
}
