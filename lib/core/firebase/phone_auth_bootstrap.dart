import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

/// ÙŠØ·Ø§Ø¨Ù‚ [firebase_auth_web] `__ff-recaptcha-container` â€” ÙˆØ¶Ø¹ Ø¹Ù„Ø§Ù…Ø© ØªÙ„Ù…ÙŠØ­ ÙÙ‚Ø· Ù„Ù„Ù…Ø·ÙˆØ±ÙŠÙ†.
/// Ø§Ù„Ù…ÙƒÙˆÙ‘Ù† Ù†ÙØ³Ù‡ Ù‚Ø¯ ÙŠÙÙ†Ø´Ø£ Ø¯ÙŠÙ†Ø§Ù…ÙŠÙƒÙŠØ§Ù‹Ø› ÙˆØ¬ÙˆØ¯ Ø¹Ù†ØµØ± Ø«Ø§Ø¨Øª ÙŠÙ‚Ù„Ù‘Ù„ Ø£Ø­ÙŠØ§Ù†Ø§Ù‹ ØªØ¹Ø§Ø±Ø¶ Ø§Ù„ØªÙˆÙ‚ÙŠØª Ù‚Ø¨Ù„ Ø£ÙˆÙ„ Ø¥Ø±Ø³Ø§Ù„ SMS.
const String kFirebaseWebRecaptchaContainerId = '__ff-recaptcha-container';

/// ØªÙ‡ÙŠØ¦Ø© reCAPTCHA Ù„Ù„ÙˆÙŠØ¨ Ù‚Ø¨Ù„ [FirebaseAuth.verifyPhoneNumber].
/// ÙŠÙØ³ØªØ¯Ø¹Ù‰ [FirebaseAuth.initializeRecaptchaConfig] Ù…Ø¹ **Ø¥Ø¹Ø§Ø¯Ø© Ù…Ø­Ø§ÙˆÙ„Ø©** (Ø´Ø¨ÙƒØ© / ØªÙ‡ÙŠØ¦Ø© JS).
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

/// ØªÙ‡ÙŠØ¦Ø© ÙˆØ§Ø­Ø¯Ø© (Ù…Ø«Ù„Ø§Ù‹ Ù…Ù† [main]) â€” Ø¨Ø¯ÙˆÙ† Ø¥Ø¹Ø§Ø¯Ø© Ù…Ø­Ø§ÙˆÙ„Ø© Ø¹Ø¯ÙˆØ§Ù†ÙŠØ©.
Future<void> ensurePhoneAuthEnvironmentReady() async {
  await ensurePhoneAuthEnvironmentReadyWithRetry(maxAttempts: 1);
}
