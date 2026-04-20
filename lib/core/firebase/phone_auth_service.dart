import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/jordan_phone.dart';

/// مصادقة الهاتف (OTP).
///
/// **Android/iOS:** [FirebaseAuth.verifyPhoneNumber].
/// **Web:** [FirebaseAuth.signInWithPhoneNumber] + [ConfirmationResult.confirm] (مسار Firebase الموصى به للويب).
abstract final class PhoneAuthService {
  static const String autoVerifiedSentinel = '__firebase_phone_auto__';
  static const String phoneAuthTemporarilyDisabledMessage =
      'تسجيل الدخول عبر الهاتف متوقف مؤقتًا. استخدم البريد الإلكتروني وكلمة المرور.';

  static ConfirmationResult? _webConfirmation;

  /// يُستدعى عند إلغاء خطوة OTP (مثلاً من [StoreController.clearPhoneVerificationState]).
  static void resetWebPendingVerification() {
    if (!kIsWeb) return;
    _webConfirmation = null;
  }

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

  static Future<({String verificationId, int? resendToken})> startVerification(
    String phoneE164, {
    int? forceResendingToken,
  }) async {
    throw FirebaseAuthException(
      code: 'operation-not-allowed',
      message: phoneAuthTemporarilyDisabledMessage,
    );
  }

  static Future<UserCredential> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    throw FirebaseAuthException(
      code: 'operation-not-allowed',
      message: phoneAuthTemporarilyDisabledMessage,
    );
  }

  static String userFacingMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'admin-restricted-operation':
        return 'عملية التحقق مقيّدة من إعدادات المشروع. تأكد من تفعيل Phone Auth، '
            'وإضافة SHA-1 وSHA-256، وتفعيل Identity Toolkit API.';
      case 'operation-not-allowed':
        return e.message?.trim().isNotEmpty == true
            ? e.message!.trim()
            : 'تسجيل الدخول بالهاتف غير مفعّل في Firebase.';
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
