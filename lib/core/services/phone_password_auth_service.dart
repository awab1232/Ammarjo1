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

  /// Sign in with phone+password via backend `POST /auth/login` (returns a Firebase custom token).
  static Future<Map<String, dynamic>> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    if (phone.trim().isEmpty || password.isEmpty) {
      throw const PhonePasswordAuthException('missing_credentials', 'أدخل رقم الهاتف وكلمة المرور.');
    }
    final uri = _authUri('/auth/login');
    final res = await http
        .post(
          uri,
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'phone': phone.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode == 401) {
      throw const PhonePasswordAuthException('invalid_login', 'رقم الهاتف أو كلمة المرور غير صحيحة.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw const PhonePasswordAuthException('login_failed', 'تعذر تسجيل الدخول. حاول مرة أخرى لاحقاً.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw const PhonePasswordAuthException('login_parse', 'رد غير صالح من الخادم.');
    }
    final m = Map<String, dynamic>.from(decoded);
    final customToken = m['customToken']?.toString().trim() ?? '';
    if (customToken.isEmpty) {
      throw const PhonePasswordAuthException('login_no_token', 'تعذر إكمال تسجيل الدخول من الخادم.');
    }
    final cred = await FirebaseAuth.instance.signInWithCustomToken(customToken);
    final firebaseUser = cred.user;
    if (firebaseUser == null) {
      throw const PhonePasswordAuthException('login_no_firebase_user', 'تعذر إنشاء جلسة Firebase بعد تسجيل الدخول.');
    }
    _lastRole = m['role']?.toString().trim();
    _lastUserId = m['userId']?.toString().trim() ?? m['firebaseUid']?.toString().trim();
    try {
      await FirebaseBackendSessionService.syncWithBackend(
        firebaseUser: firebaseUser,
        customToken: customToken,
      );
    } on Object {
      // best effort — session is still a valid Firebase custom-token session
    }
    return m;
  }
}
