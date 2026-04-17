import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';

/// Thrown by [PhonePasswordAuthService] with a user-friendly Arabic message
/// so callers can `catch` and surface it directly.
class PhonePasswordAuthException implements Exception {
  const PhonePasswordAuthException(this.code, this.messageAr);

  final String code;
  final String messageAr;

  @override
  String toString() => 'PhonePasswordAuthException($code): $messageAr';
}

/// Talks to the backend `/auth/login` and `/auth/password` endpoints (the
/// phone + password flow) and, on success, signs the user into Firebase using
/// the custom token the backend minted.
class PhonePasswordAuthService {
  const PhonePasswordAuthService._();

  static const Duration _timeout = Duration(seconds: 20);

  static Uri _buildUri(String path) {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      throw const PhonePasswordAuthException('backend_unavailable', 'الخدمة غير متاحة حالياً، حاول لاحقاً');
    }
    return Uri.parse('$base$path');
  }

  static String _mapErrorCodeAr(String code) {
    switch (code) {
      case 'invalid_phone':
        return 'رقم الهاتف غير صحيح';
      case 'password_required':
        return 'الرجاء إدخال كلمة المرور';
      case 'password_too_short':
        return 'كلمة المرور قصيرة — 6 أحرف على الأقل';
      case 'password_too_long':
        return 'كلمة المرور طويلة جداً';
      case 'invalid_credentials':
        return 'رقم الهاتف أو كلمة المرور غير صحيحة';
      case 'account_disabled':
        return 'تم تعطيل هذا الحساب';
      case 'password_not_set':
        return 'هذا الحساب بدون كلمة مرور. أعد إنشاء الحساب أو تواصل مع الدعم.';
      case 'not_authenticated':
        return 'انتهت جلسة التحقق، أعد إدخال رمز OTP';
      case 'firebase_uid_missing':
        return 'تعذر التحقق من الحساب';
      case 'token_mint_failed':
        return 'تعذر إصدار رمز الدخول، حاول مرة أخرى';
      case 'backend_unavailable':
        return 'الخدمة غير متاحة حالياً، حاول لاحقاً';
      default:
        return 'حدث خطأ غير متوقع، حاول مرة أخرى';
    }
  }

  /// Sign in with phone + password. On success the Firebase user is signed
  /// in via the custom token; the returned [UserCredential] exposes the ID
  /// token you can forward to other backend APIs.
  static Future<UserCredential> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    final uri = _buildUri('/auth/login');
    final bodyJson = jsonEncode({'phone': phone, 'password': password});

    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: bodyJson,
          )
          .timeout(_timeout);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('PhonePasswordAuth: login network error $e');
      throw const PhonePasswordAuthException(
        'backend_unavailable',
        'تعذر الاتصال بالخادم، تحقق من الإنترنت',
      );
    }

    final decoded = _safeDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final code = _extractErrorCode(decoded) ?? 'invalid_credentials';
      throw PhonePasswordAuthException(code, _mapErrorCodeAr(code));
    }

    final token = decoded?['customToken'];
    if (token is! String || token.trim().isEmpty) {
      throw const PhonePasswordAuthException(
        'token_mint_failed',
        'تعذر إصدار رمز الدخول، حاول مرة أخرى',
      );
    }
    try {
      return await FirebaseAuth.instance.signInWithCustomToken(token);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) debugPrint('PhonePasswordAuth: signInWithCustomToken failed ${e.code}');
      throw PhonePasswordAuthException(
        'firebase_sign_in_failed',
        'فشل تسجيل الدخول عبر Firebase (${e.code})',
      );
    }
  }

  /// Attach a password + phone to the currently signed-in Firebase user.
  /// Call this after OTP verification during signup.
  static Future<void> setPasswordForCurrentUser({
    required String phone,
    required String password,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const PhonePasswordAuthException(
        'not_authenticated',
        'انتهت جلسة التحقق، أعد إدخال رمز OTP',
      );
    }
    String? idToken;
    try {
      idToken = await user.getIdToken(true);
    } on Object {
      idToken = null;
    }
    if (idToken == null || idToken.isEmpty) {
      throw const PhonePasswordAuthException(
        'not_authenticated',
        'انتهت جلسة التحقق، أعد إدخال رمز OTP',
      );
    }

    final uri = _buildUri('/auth/password');
    final bodyJson = jsonEncode({'phone': phone, 'password': password});

    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: bodyJson,
          )
          .timeout(_timeout);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('PhonePasswordAuth: set-password network error $e');
      throw const PhonePasswordAuthException(
        'backend_unavailable',
        'تعذر الاتصال بالخادم، تحقق من الإنترنت',
      );
    }

    final decoded = _safeDecode(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final code = _extractErrorCode(decoded) ?? 'backend_unavailable';
      throw PhonePasswordAuthException(code, _mapErrorCodeAr(code));
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  static Map<String, dynamic>? _safeDecode(String body) {
    if (body.isEmpty) return null;
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
    } on Object {
      return null;
    }
    return null;
  }

  static String? _extractErrorCode(Map<String, dynamic>? decoded) {
    if (decoded == null) return null;
    final direct = decoded['code'] ?? decoded['error'] ?? decoded['message'];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();
    return null;
  }
}
