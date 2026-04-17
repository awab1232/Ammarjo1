import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// [Firebase App Check](https://firebase.google.com/docs/app-check) Ã™Å Ã˜Â«Ã˜Â¨Ã˜Âª Ã˜Â£Ã™â€  Ã˜Â§Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª Ã™â€šÃ˜Â§Ã˜Â¯Ã™â€¦Ã˜Â© Ã™â€¦Ã™â€  Ã˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€šÃ™Æ’ Ã˜Â§Ã™â€žÃ˜Â­Ã™â€šÃ™Å Ã™â€šÃ™Å  Ã™Ë†Ã™â€žÃ™Å Ã˜Â³ Ã™â€¦Ã™â€  Ã˜Â³Ã™Æ’Ã˜Â±Ã˜Â¨Ã˜Âª Ã˜Â¹Ã˜Â´Ã™Ë†Ã˜Â§Ã˜Â¦Ã™Å .
///
/// Ã˜Â¥Ã™â€  Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€žÃ˜Âª **Enforce** Ã™ÂÃ™Å  Console Ã™â€žÃ™â‚¬ Firestore/Storage/Functions Ã˜Â¯Ã™Ë†Ã™â€  Ã™â€¦Ã˜Â²Ã™Ë†Ã™â€˜Ã˜Â¯ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€šÃ˜Å’ Ã˜ÂªÃ˜Â­Ã˜ÂµÃ™â€ž Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â±Ã™ÂÃ˜Â¶ Ã˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª Ã˜Â£Ã™Ë† Ã˜ÂªÃ˜Â­Ã˜Â°Ã™Å Ã˜Â±Ã˜Â§Ã˜Âª Ã™â€¦Ã˜Â«Ã™â€ž
/// `No AppCheckProvider installed`.
Future<void> activateFirebaseAppCheck() async {
  if (Firebase.apps.isEmpty) return;
  if (kIsWeb) {
    // Ã™â€žÃ™â€žÃ™Ë†Ã™Å Ã˜Â¨: Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€ž reCAPTCHA v3 Ã™ÂÃ™Å  Console Ã˜Â«Ã™â€¦ Ã™â€¦Ã˜Â±Ã™â€˜Ã˜Â± Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­:
    // await FirebaseAppCheck.instance.activate(
    //   providerWeb: ReCaptchaV3Provider('Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­-Ã˜Â§Ã™â€žÃ™â€¦Ã™Ë†Ã™â€šÃ˜Â¹-Ã™â€¦Ã™â€ -Console'),
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
        'Firebase App Check: Ã™â€¦Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€ž (Android/iOS debug). Ã˜Â£Ã˜Â¶Ã™Â Ã˜Â±Ã™â€¦Ã˜Â² Ã˜Â§Ã™â€žÃ˜ÂªÃ˜ÂµÃ˜Â­Ã™Å Ã˜Â­ Ã™â€¦Ã™â€  Logcat Ã˜Â¥Ã™â€žÃ™â€° Console Ã¢â€ â€™ App Check Ã¢â€ â€™ Debug token Ã˜Â¥Ã™â€  Ã™â€žÃ˜Â²Ã™â€¦.',
      );
    }
  } on Object {
    debugPrint('Firebase App Check: activate failed: unexpected error\n$StackTrace.current');
  }
}

