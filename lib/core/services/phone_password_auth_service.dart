import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../utils/jordan_phone.dart';
import 'firebase_auth_header_provider.dart';
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

  /// Sign in with phone+password in Firebase, then bind backend session using ID token.
  static Future<UserCredential> signInWithPhonePassword({
    required String phone,
    required String password,
  }) async {
    final String email;
    try {
      email = phoneToEmail(phone);
    } on FormatException {
      throw const PhonePasswordAuthException(
        'invalid_phone',
        'رقم الهاتف غير صالح',
      );
    }
    debugPrint('[AUTH-AUDIT] login phoneToEmail (internal, not shown in UI): $email');
    UserCredential credential;
    try {
      credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException {
      throw const PhonePasswordAuthException(
        'invalid_credentials',
        'رقم الهاتف أو كلمة المرور غير صحيحة',
      );
    }

    // ignore: avoid_print
    print('🔥 USER SIGNED IN');
    try {
      await FirebaseAuthHeaderProvider.requireIdToken(reason: 'phone_password_service_signin');
      final res = await FirebaseBackendSessionService.syncWithBackend(firebaseUser: credential.user);
      // ignore: avoid_print
      print('🔥 BACKEND SYNC CALLED');
      // ignore: avoid_print
      print('LOGIN SUCCESS');
      // ignore: avoid_print
      print('BACKEND RESPONSE: $res');
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
