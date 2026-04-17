import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'phone_auth_bootstrap.dart';
import '../utils/jordan_phone.dart';

/// Ã™â€¦Ã˜ÂµÃ˜Â§Ã˜Â¯Ã™â€šÃ˜Â© Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â Ã˜Â¹Ã˜Â¨Ã˜Â± [FirebaseAuth.verifyPhoneNumber] (Ã˜Â¹Ã™â€¦Ã™Å Ã™â€ž Ã™ÂÃ™â€šÃ˜Â·).
/// **Ã˜Â§Ã™â€žÃ™Ë†Ã™Å Ã˜Â¨:** reCAPTCHA **invisible** Ã™Å Ã˜Â¶Ã˜Â¨Ã˜Â·Ã™â€¡ [firebase_auth_web] Ã˜ÂªÃ™â€žÃ™â€šÃ˜Â§Ã˜Â¦Ã™Å Ã˜Â§Ã™â€¹ Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ [RecaptchaVerifier] Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  Ã˜Â­Ã˜Â§Ã™Ë†Ã™Å Ã˜Â© Ã™â€¦Ã˜Â®Ã˜ÂµÃ˜ÂµÃ˜Â©.
abstract final class PhoneAuthService {
  static const String autoVerifiedSentinel = '__firebase_phone_auto__';

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

  /// Ã™Å Ã˜Â´Ã˜ÂºÃ™â€˜Ã™â€ž [verifyPhoneNumber] Ã™â€¦Ã˜Â±Ã˜Â© Ã™Ë†Ã˜Â§Ã˜Â­Ã˜Â¯Ã˜Â© Ã™â€¦Ã˜Â¹ Ã˜Â¥Ã™Æ’Ã™â€¦Ã˜Â§Ã™â€ž [verificationCompleted] / [codeSent] / [verificationFailed].
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
          FirebaseAuthException(code: 'verify-failed', message: 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â¨Ã˜Â¯Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š.'),
        );
      }
    } on Object {
      if (!completer.isCompleted) {
        completer.completeError(
          FirebaseAuthException(code: 'unknown', message: 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â¨Ã˜Â¯Ã˜Â¡ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š.'),
        );
      }
    }

    return completer.future.timeout(
      const Duration(seconds: 125),
      onTimeout: () {
        throw FirebaseAuthException(
          code: 'timeout',
          message: 'Ã˜Â§Ã™â€ Ã˜ÂªÃ™â€¡Ã˜Âª Ã™â€¦Ã™â€¡Ã™â€žÃ˜Â© Ã˜Â§Ã™â€ Ã˜ÂªÃ˜Â¸Ã˜Â§Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã˜Â¨Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â.',
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

    if (kIsWeb) {
      try {
        await ensurePhoneAuthEnvironmentReadyWithRetry();
      } on Object {
        throw FirebaseAuthException(
          code: 'recaptcha-config-failed',
          message: 'Ã™ÂÃ˜Â´Ã™â€ž Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© reCAPTCHA Ã™â€žÃ™â€žÃ™Ë†Ã™Å Ã˜Â¨.',
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
  }) {
    final cred = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return FirebaseAuth.instance.signInWithCredential(cred);
  }

  static String userFacingMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'admin-restricted-operation':
        return 'Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™â€žÃ™Å Ã˜Â© Ã™â€¦Ã™â€šÃ™Å Ã™â€˜Ã˜Â¯Ã˜Â© Ã™â€¦Ã™â€  Ã˜Â¥Ã˜Â¹Ã˜Â¯Ã˜Â§Ã˜Â¯Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜Â±Ã™Ë†Ã˜Â¹ (Ã™â€žÃ™Å Ã˜Â³ Ã˜Â¨Ã˜Â³Ã˜Â¨Ã˜Â¨ Ã™Æ’Ã™Ë†Ã˜Â¯ Admin SDK Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š). '
            'Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€ : (1) Firebase Console Ã¢â€ â€™ Authentication Ã¢â€ â€™ Sign-in method Ã¢â€ â€™ Phone Ã™â€¦Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€ž. '
            '(2) Google Cloud Console Ã¢â€ â€™ APIs Ã¢â€ â€™ Identity Toolkit API Ã™â€¦Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€ž. '
            '(3) Ã™â€¦Ã™ÂÃ˜Â§Ã˜ÂªÃ™Å Ã˜Â­ API: Ã™â€žÃ˜Â§ Ã˜ÂªÃ™â€šÃ™Å Ã™â€˜Ã˜Â¯ Ã™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­ Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜ÂµÃ™ÂÃ˜Â­/Ã˜Â£Ã™â€ Ã˜Â¯Ã˜Â±Ã™Ë†Ã™Å Ã˜Â¯ Ã˜Â¨Ã˜Â­Ã™Å Ã˜Â« Ã™Å Ã™â€¦Ã™â€ Ã˜Â¹ Identity Toolkit. '
            '(4) Ã™â€žÃ™â€žÃ™Ë†Ã™Å Ã˜Â¨: Authentication Ã¢â€ â€™ Settings Ã¢â€ â€™ Authorized domains Ã™Å Ã˜ÂªÃ˜Â¶Ã™â€¦Ã™â€  Ã™â€ Ã˜Â·Ã˜Â§Ã™â€šÃ™Æ’ Ã™Ë†localhost. '
            '(5) Ã˜Â£Ã˜Â¶Ã™Â SHA-1 Ã™Ë†SHA-256 Ã™ÂÃ™Å  Ã˜Â¥Ã˜Â¹Ã˜Â¯Ã˜Â§Ã˜Â¯Ã˜Â§Ã˜Âª Ã˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š Ã˜Â£Ã™â€ Ã˜Â¯Ã˜Â±Ã™Ë†Ã™Å Ã˜Â¯. '
            '(6) Ã˜ÂªÃ™ÂÃ˜Â¹Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ™ÂÃ™Ë†Ã˜ÂªÃ˜Â±Ã˜Â© Ã˜Â¥Ã™â€  Ã˜Â·Ã™â€žÃ˜Â¨Ã˜ÂªÃ™â€¡ Google Ã™â€žÃ™â€¡Ã˜Â°Ã™â€¡ Ã˜Â§Ã™â€žÃ˜Â®Ã˜Â¯Ã™â€¦Ã˜Â©.';
      case 'operation-not-allowed':
        return 'Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã˜Â¨Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€ž. Ã™â€¦Ã™â€  Firebase Console Ã¢â€ â€™ Authentication Ã¢â€ â€™ Sign-in method Ã™ÂÃ˜Â¹Ã™â€˜Ã™â€ž Phone.';
      case 'app-not-authorized':
        return 'Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜ÂµÃ˜Â±Ã™â€˜Ã˜Â­ Ã˜Â¨Ã™â€¡ Ã™â€žÃ™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã™ÂÃ˜ÂªÃ˜Â§Ã˜Â­. Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  google-services.json Ã™Ë†firebase_options Ã™Ë†Package name / SHA.';
      case 'unauthorized-domain':
        return _unauthorizedDomainMessage;
      case 'recaptcha-config-failed':
        return e.message ?? 'Ã™ÂÃ˜Â´Ã™â€ž Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© reCAPTCHA Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ™Ë†Ã™Å Ã˜Â¨. Ã˜Â£Ã˜Â¹Ã˜Â¯ Ã˜ÂªÃ˜Â­Ã™â€¦Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â© Ã™Ë†Ã˜Â¬Ã˜Â±Ã˜Â¨ Ã™â€¦Ã˜ÂªÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â§Ã™â€¹ Ã˜Â¢Ã˜Â®Ã˜Â±.';
      case 'too-many-requests':
        return 'Ã˜ÂªÃ™â€¦ Ã˜Â±Ã™ÂÃ˜Â¶ Ã˜Â§Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨ Ã™â€¦Ã˜Â¤Ã™â€šÃ˜ÂªÃ˜Â§Ã™â€¹ Ã˜Â¨Ã˜Â³Ã˜Â¨Ã˜Â¨ Ã™Æ’Ã˜Â«Ã˜Â±Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€žÃ˜Â§Ã˜Âª. Ã˜Â§Ã™â€ Ã˜ÂªÃ˜Â¸Ã˜Â± Ã˜Â«Ã™â€¦ Ã˜Â£Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€žÃ˜Â© Ã™â€¦Ã™â€  Ã˜Â´Ã˜Â¨Ã™Æ’Ã˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€° Ã˜Â¥Ã™â€  Ã™â€žÃ˜Â²Ã™â€¦.';
      case 'quota-exceeded':
        return 'Ã˜ÂªÃ˜Â¬Ã˜Â§Ã™Ë†Ã˜Â²Ã˜Âª Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â³Ã˜Â§Ã˜Â¦Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã™â€¦Ã™Ë†Ã˜Â­. Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã™â€žÃ˜Â§Ã˜Â­Ã™â€šÃ˜Â§Ã™â€¹.';
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return 'Ã˜ÂªÃ˜Â£Ã™Æ’Ã˜Â¯ Ã™â€¦Ã™â€  Ã˜Â¥Ã˜Â¯Ã˜Â®Ã˜Â§Ã™â€ž Ã˜Â±Ã™â€šÃ™â€¦ Ã˜Â£Ã˜Â±Ã˜Â¯Ã™â€ Ã™Å  Ã˜ÂµÃ˜Â­Ã™Å Ã˜Â­ Ã™Å Ã˜Â¨Ã˜Â¯Ã˜Â£ Ã˜Â¨Ã™â‚¬ 7 (Ã™Â© Ã˜Â£Ã˜Â±Ã™â€šÃ˜Â§Ã™â€¦).';
      case 'invalid-verification-code':
        return 'Ã˜Â±Ã™â€¦Ã˜Â² Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã˜ÂºÃ™Å Ã˜Â± Ã˜ÂµÃ˜Â­Ã™Å Ã˜Â­. Ã˜Â£Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â¥Ã˜Â¯Ã˜Â®Ã˜Â§Ã™â€ž Ã˜Â£Ã™Ë† Ã˜Â§Ã˜Â·Ã™â€žÃ˜Â¨ Ã˜Â±Ã™â€¦Ã˜Â²Ã˜Â§Ã™â€¹ Ã˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯Ã˜Â§Ã™â€¹.';
      case 'session-expired':
        return 'Ã˜Â§Ã™â€ Ã˜ÂªÃ™â€¡Ã˜Âª Ã˜ÂµÃ™â€žÃ˜Â§Ã˜Â­Ã™Å Ã˜Â© Ã˜Â¬Ã™â€žÃ˜Â³Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š. Ã˜Â§Ã˜Â¨Ã˜Â¯Ã˜Â£ Ã˜Â®Ã˜Â·Ã™Ë†Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â¥Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€ž Ã™â€¦Ã™â€  Ã˜Â¬Ã˜Â¯Ã™Å Ã˜Â¯.';
      case 'network-request-failed':
        return 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â§Ã˜ÂªÃ˜ÂµÃ˜Â§Ã™â€ž Ã˜Â¨Ã˜Â®Ã˜Â¯Ã™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š. Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€ Ã˜ÂªÃ˜Â±Ã™â€ Ã˜Âª.';
      case 'captcha-check-failed':
      case 'missing-client-identifier':
        return _captchaFailedMessage;
      case 'timeout':
        return e.message ?? 'Ã˜Â§Ã™â€ Ã˜ÂªÃ™â€¡Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã™â€¡Ã™â€žÃ˜Â©. Ã˜Â£Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€žÃ˜Â©.';
      default:
        final m = e.message?.trim();
        if (m != null && m.isNotEmpty) return m;
        return 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â¥Ã˜ÂªÃ™â€¦Ã˜Â§Ã™â€¦ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š (unexpected error). Ã˜Â­Ã˜Â§Ã™Ë†Ã™â€ž Ã™â€¦Ã˜Â±Ã˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€°.';
    }
  }

  static const String _unauthorizedDomainMessage =
      'Ã˜Â§Ã™â€žÃ™â€ Ã˜Â·Ã˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å  Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â¶Ã˜Â§Ã™Â Ã™ÂÃ™Å  Firebase. Ã˜Â§Ã™ÂÃ˜ÂªÃ˜Â­ Console Ã¢â€ â€™ Authentication Ã¢â€ â€™ Settings Ã¢â€ â€™ '
      'Authorized domains Ã™Ë†Ã˜Â£Ã˜Â¶Ã™Â: localhostÃ˜Å’ 127.0.0.1Ã˜Å’ Ã™Ë†Ã™â€ Ã˜Â·Ã˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ˜Â§Ã˜Â³Ã˜ÂªÃ˜Â¶Ã˜Â§Ã™ÂÃ˜Â© Ã˜Â§Ã™â€žÃ™ÂÃ˜Â¹Ã™â€žÃ™Å  (Ã™â€¦Ã˜Â«Ã™â€ž app.web.app Ã˜Â£Ã™Ë† Ã™â€ Ã˜Â·Ã˜Â§Ã™â€šÃ™Æ’ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â®Ã˜ÂµÃ˜Âµ). '
      'Ã˜Â«Ã™â€¦ Ã˜Â£Ã˜Â¹Ã˜Â¯ Ã˜ÂªÃ˜Â­Ã™â€¦Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â©.';

  static const String _captchaFailedMessage =
      'Ã™ÂÃ˜Â´Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã˜Â§Ã™â€žÃ˜Â£Ã™â€¦Ã™â€ Ã™Å  (reCAPTCHA invisible). Ã˜Â¬Ã˜Â±Ã™â€˜Ã˜Â¨: (1) Ã˜Â¥Ã˜Â¶Ã˜Â§Ã™ÂÃ˜Â© Ã™â€ Ã˜Â·Ã˜Â§Ã™â€š Ã˜Â§Ã™â€žÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â© Ã˜Â¶Ã™â€¦Ã™â€  Authorized domains Ã™ÂÃ™Å  Firebase. '
      '(2) Ã˜ÂªÃ˜Â¹Ã˜Â·Ã™Å Ã™â€ž Ã˜Â­Ã˜Â§Ã˜Â¬Ã˜Â¨ Ã˜Â§Ã™â€žÃ˜Â¥Ã˜Â¹Ã™â€žÃ˜Â§Ã™â€ Ã˜Â§Ã˜Âª/Ã˜Â§Ã™â€žÃ˜Â®Ã˜ÂµÃ™Ë†Ã˜ÂµÃ™Å Ã˜Â© Ã™â€žÃ™â€¡Ã˜Â°Ã˜Â§ Ã˜Â§Ã™â€žÃ™â€¦Ã™Ë†Ã™â€šÃ˜Â¹. (3) Ã˜Â¥Ã˜Â¹Ã˜Â§Ã˜Â¯Ã˜Â© Ã˜ÂªÃ˜Â­Ã™â€¦Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â© Ã™Ë†Ã˜Â§Ã™â€žÃ˜Â¶Ã˜ÂºÃ˜Â· Ã˜Â¹Ã™â€žÃ™â€° Ã‚Â«Ã˜Â¥Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â±Ã™â€¦Ã˜Â²Ã‚Â» Ã™â€¦Ã˜Â±Ã˜Â© Ã˜Â£Ã˜Â®Ã˜Â±Ã™â€° '
      '(Ã™Å Ã™ÂÃ˜Â¹Ã˜Â§Ã˜Â¯ Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© reCAPTCHA Ã˜ÂªÃ™â€žÃ™â€šÃ˜Â§Ã˜Â¦Ã™Å Ã˜Â§Ã™â€¹). (4) Ã™â€¦Ã˜ÂªÃ˜ÂµÃ™ÂÃ˜Â­Ã˜Â§Ã™â€¹ Ã˜Â¢Ã˜Â®Ã˜Â± Ã˜Â£Ã™Ë† Ã™â€ Ã˜Â§Ã™ÂÃ˜Â°Ã˜Â© Ã˜Â®Ã˜Â§Ã˜ÂµÃ˜Â©.';

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

