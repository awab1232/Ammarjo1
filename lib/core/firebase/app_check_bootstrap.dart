import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// [Firebase App Check](https://firebase.google.com/docs/app-check) يثبت أن الطلبات قادمة من تطبيقك الحقيقي وليس من سكربت عشوائي.
///
/// إن فعّلت **Enforce** في Console لـ Firestore/Storage/Functions دون مزوّد في التطبيق، تحصل على رفض طلبات أو تحذيرات مثل
/// `No AppCheckProvider installed`.
Future<void> activateFirebaseAppCheck() async {
  if (Firebase.apps.isEmpty) return;
  if (kIsWeb) {
    // للويب: سجّل reCAPTCHA v3 في Console ثم مرّر المفتاح:
    // await FirebaseAppCheck.instance.activate(
    //   providerWeb: ReCaptchaV3Provider('مفتاح-الموقع-من-Console'),
    // );
    return;
  }
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    if (kDebugMode) {
      debugPrint(
        'Firebase App Check: مفعّل (Android/iOS debug). أضف رمز التصحيح من Logcat إلى Console → App Check → Debug token إن لزم.',
      );
    }
  } on Object catch (e, st) {
    debugPrint('Firebase App Check: activate failed: $e\n$st');
  }
}
