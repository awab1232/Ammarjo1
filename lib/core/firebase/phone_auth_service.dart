import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'phone_auth_bootstrap.dart';
import '../services/firebase_backend_session_service.dart';
import '../utils/jordan_phone.dart';

/// مصادقة الهاتف عبر [FirebaseAuth.verifyPhoneNumber] (OTP).
abstract final class PhoneAuthService {
  static const String autoVerifiedSentinel = '__firebase_phone_auto__';
  static const String webConfirmationSentinel = '__firebase_web_confirmation__';
  static ConfirmationResult? _webConfirmationResult;

  static String jordanPhoneE164(String localNineDigits) {
    final u = normalizeJordanPhoneForUsername(localNineDigits);
    return '+$u';
  }

  static bool isValidE164Jordan(String phoneE164) {
    final t = phoneE164.trim();
    if (!t.startsWith('+')) return false;
    final d = t.replaceAll(RegExp(r'\D'), '');
    return d.length == 12 && d.startsWith('962') && d[3] == '7';
  }

  /// تشغيل [verifyPhoneNumber] مرة واحدة وإرجاع verificationId/resendToken.
  static Future<({String verificationId, int? resendToken})> _verifyPhoneNumberOnce(
    FirebaseAuth auth,
    String trimmedE164, {
    int? forceResendingToken,
  }) async {
    final completer = Completer<({String verificationId, int? resendToken})>();

    try {
      await auth.verifyPhoneNumber(
        phoneNumber: trimmedE164,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await auth.signInWithCredential(credential);
          final signed = auth.currentUser;
          if (signed != null) {
            try {
              await FirebaseBackendSessionService.syncWithBackend(firebaseUser: signed);
            } on Object catch (e) {
              debugPrint('[PhoneAuthService] auto-verify syncWithBackend: $e');
            }
          }
          if (!completer.isCompleted) {
            completer.complete((verificationId: autoVerifiedSentinel, resendToken: null));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!completer.isCompleted) {
            completer.complete((verificationId: verificationId, resendToken: resendToken));
          }
        },
        codeAutoRetrievalTimeout: (_) {},
        timeout: const Duration(seconds: 120),
        forceResendingToken: forceResendingToken,
      );
    } on FirebaseAuthException {
      if (!completer.isCompleted) {
        completer.completeError(
          FirebaseAuthException(code: 'verify-failed', message: 'تعذر بدء التحقق.'),
        );
      }
    } on Object {
      if (!completer.isCompleted) {
        completer.completeError(
          FirebaseAuthException(code: 'unknown', message: 'تعذر بدء التحقق.'),
        );
      }
    }

    return completer.future.timeout(
      const Duration(seconds: 125),
      onTimeout: () {
        throw FirebaseAuthException(
          code: 'timeout',
          message: 'انتهت مهلة انتظار التحقق بالهاتف.',
        );
      },
    );
  }

  static Future<({String verificationId, int? resendToken})> startVerification(
    String phoneE164, {
    int? forceResendingToken,
  }) async {
    final trimmed = phoneE164.trim();
    if (!isValidE164Jordan(trimmed)) {
      throw FirebaseAuthException(
        code: 'invalid-phone-number',
        message: 'Expected Jordan mobile E.164 like +9627XXXXXXXX',
      );
    }

    final auth = FirebaseAuth.instance;
    await auth.setLanguageCode('ar');
    debugPrint('PHONE AUTH START');

    if (kIsWeb) {
      try {
        final confirmation = await auth.signInWithPhoneNumber(trimmed);
        _webConfirmationResult = confirmation;
        debugPrint('OTP SENT');
        return (verificationId: webConfirmationSentinel, resendToken: null);
      } on FirebaseAuthException catch (e) {
        debugPrint('PHONE AUTH ERROR: $e');
        rethrow;
      } on Object catch (e) {
        debugPrint('PHONE AUTH ERROR: $e');
        throw FirebaseAuthException(
          code: 'recaptcha-config-failed',
          message: 'فشل تهيئة reCAPTCHA للويب.',
        );
      }
    }

    Future<({String verificationId, int? resendToken})> run() =>
        _verifyPhoneNumberOnce(auth, trimmed, forceResendingToken: forceResendingToken);

    try {
      return await run();
    } on FirebaseAuthException {
      if (kIsWeb) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await ensurePhoneAuthEnvironmentReadyWithRetry(maxAttempts: 2).onError((_, _) => null);
        return await run();
      }
      rethrow;
    }
  }

  static Future<UserCredential> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (kIsWeb) {
      try {
        final confirmation = _webConfirmationResult;
        if (confirmation == null) {
          throw FirebaseAuthException(
            code: 'session-expired',
            message: 'انتهت جلسة التحقق. أعد إرسال الرمز.',
          );
        }
        final cred = await confirmation.confirm(smsCode.trim());
        debugPrint('USER UID: ${cred.user?.uid}');
        await _syncBackendAfterOtp(cred.user);
        return cred;
      } on Object catch (e) {
        debugPrint('PHONE AUTH ERROR: $e');
        rethrow;
      }
    }
    final cred = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    final out = await FirebaseAuth.instance.signInWithCredential(cred);
    debugPrint('USER UID: ${out.user?.uid}');
    await _syncBackendAfterOtp(out.user);
    return out;
  }

  static Future<void> _syncBackendAfterOtp(User? u) async {
    if (u == null) return;
    try {
      await FirebaseBackendSessionService.syncWithBackend(firebaseUser: u);
    } on Object catch (e) {
      debugPrint('[PhoneAuthService] OTP sign-in syncWithBackend: $e');
    }
  }

  static String userFacingMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'admin-restricted-operation':
        return 'عملية التحقق مقيّدة من إعدادات المشروع. تأكد من تفعيل Phone Auth، '
            'وإضافة SHA-1 وSHA-256، وتفعيل Identity Toolkit API.';
      case 'operation-not-allowed':
        return 'تسجيل الدخول بالهاتف غير مفعّل في Firebase.';
      case 'app-not-authorized':
        return 'هذا التطبيق غير مصرح له باستخدام Phone Auth. تحقق من إعدادات Firebase وملفات التهيئة.';
      case 'unauthorized-domain':
        return _unauthorizedDomainMessage;
      case 'recaptcha-config-failed':
        return e.message ?? 'فشل تهيئة reCAPTCHA على الويب. أعد تحميل الصفحة وحاول مجددًا.';
      case 'too-many-requests':
        return 'عدد المحاولات كبير. انتظر قليلًا ثم أعد المحاولة.';
      case 'quota-exceeded':
        return 'تم تجاوز حصة إرسال الرسائل. حاول لاحقًا.';
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return 'تأكد من إدخال رقم أردني صحيح بصيغة 07XXXXXXXX.';
      case 'invalid-verification-code':
        return 'رمز التحقق غير صحيح.';
      case 'session-expired':
        return 'انتهت صلاحية جلسة التحقق. أعد إرسال الرمز.';
      case 'network-request-failed':
        return 'تعذر الاتصال بخدمة التحقق. تحقق من الإنترنت.';
      case 'captcha-check-failed':
      case 'missing-client-identifier':
        return _captchaFailedMessage;
      case 'timeout':
        return e.message ?? 'انتهت المهلة. أعد المحاولة.';
      default:
        final m = e.message?.trim();
        if (m != null && m.isNotEmpty) return m;
        return 'تعذر إتمام التحقق. حاول مرة أخرى.';
    }
  }

  static const String _unauthorizedDomainMessage =
      'النطاق الحالي غير مصرح به في Firebase. أضف النطاق في Authentication > Settings > Authorized domains.';

  static const String _captchaFailedMessage =
      'فشل التحقق الأمني (reCAPTCHA). أعد تحميل الصفحة أو جرّب متصفحًا آخر.';

  static String? jordanUsernameFromFirebaseUser(User? u) {
    if (u == null) return '';
    final p = u.phoneNumber;
    if (p == null || p.isEmpty) return '';
    var d = p.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.length == 9 && d.startsWith('7')) {
      return '962$d';
    }
    if (d.startsWith('962') && d.length >= 12) {
      return d.length > 12 ? d.substring(0, 12) : d;
    }
    return d.isNotEmpty ? d : '';
  }
}

