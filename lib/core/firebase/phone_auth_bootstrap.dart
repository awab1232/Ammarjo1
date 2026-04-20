import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

/// يطابق [firebase_auth_web] — الحاوية الافتراضية لـ reCAPTCHA (لا تستخدم `recaptcha-container`).
/// المكوّن يُنشأ عادةً ديناميكياً تحت [document.documentElement]؛ أنماط [web/index.html] ترفع z-index فوق كانفاس Flutter.
const String kFirebaseWebRecaptchaContainerId = '__ff-recaptcha-container';

/// تهيئة reCAPTCHA للويب قبل [FirebaseAuth.verifyPhoneNumber].
/// يُستدعى [FirebaseAuth.initializeRecaptchaConfig] مع **إعادة محاولة** (شبكة / تهيئة JS).
Future<void> ensurePhoneAuthEnvironmentReadyWithRetry({int maxAttempts = 3}) async {
  if (Firebase.apps.isEmpty || !kIsWeb) return;
  Object? lastError;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      await FirebaseAuth.instance.initializeRecaptchaConfig();
      if (kDebugMode) {
        debugPrint('PhoneAuth: initializeRecaptchaConfig succeeded (attempt ${attempt + 1}/$maxAttempts).');
      }
      return;
    } on Object {
      lastError = 'unexpected error';
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
  }
  throw lastError ?? StateError('initializeRecaptchaConfig failed after $maxAttempts attempts');
}

/// تهيئة واحدة (مثلاً من [main]) — بدون إعادة محاولة عدوانية.
Future<void> ensurePhoneAuthEnvironmentReady() async {
  await ensurePhoneAuthEnvironmentReadyWithRetry(maxAttempts: 1);
}
