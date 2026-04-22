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
    final normalized = normalizeJordanPhoneForUsername(phone);
    final email = syntheticEmailForPhone(normalized);
    debugPrint('[AUTH-AUDIT] login synthetic email: $email');
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

    try {
      await FirebaseAuthHeaderProvider.requireIdToken(reason: 'phone_password_service_signin');
      await FirebaseBackendSessionService.syncWithBackend(firebaseUser: credential.user);
      debugPrint('[AUTH-AUDIT] login backend sync success for uid=${credential.user?.uid}');
      return credential;
    } on Object {
      await FirebaseAuth.instance.signOut();
      throw const PhonePasswordAuthException(
        'backend_unavailable',
        'تم تسجيل الدخول في Firebase لكن تعذر ربط الجلسة مع الخادم',
      );
    }
  }
}
