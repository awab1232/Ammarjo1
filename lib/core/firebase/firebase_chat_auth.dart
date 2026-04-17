import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Ã˜Â­Ã˜Â³Ã˜Â§Ã˜Â¨ Firebase Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯Ã™Å  Ã™â€¦Ã˜Â´Ã˜ÂªÃ™â€š Ã™â€žÃ™â€žÃ˜Â¶Ã™Å Ã™Â Ã˜Â£Ã™Ë† Ã˜Â¹Ã™â€ Ã˜Â¯ Ã˜Â¹Ã˜Â¯Ã™â€¦ Ã™Ë†Ã˜Â¬Ã™Ë†Ã˜Â¯ Ã˜Â¬Ã™â€žÃ˜Â³Ã˜Â© Ã™â€¡Ã˜Â§Ã˜ÂªÃ™Â (Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã™â€¦Ã˜Â´Ã˜ÂªÃ™â€šÃ˜Â© Ã™â€¦Ã˜Â­Ã™â€žÃ™Å Ã˜Â§Ã™â€¹).
///
/// Ã˜ÂªÃ™ÂÃ˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ [buyer_id] / [seller_id] Ã™ÂÃ™Å  Ã™â€šÃ™Ë†Ã˜Â§Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜Â£Ã™â€¦Ã˜Â§Ã™â€ . Ã™â€žÃ˜Â§ Ã˜ÂªÃ˜Â´Ã˜Â§Ã˜Â±Ã™Æ’ [appSalt] Ã˜Â¹Ã™â€žÃ™â€ Ã˜Â§Ã™â€¹ Ã™ÂÃ™Å  Ã˜Â¥Ã™â€ Ã˜ÂªÃ˜Â§Ã˜Â¬ Ã˜Â­Ã™â€šÃ™Å Ã™â€šÃ™Å 
/// Ã˜Â¨Ã˜Â¯Ã™Å Ã™â€ž: Custom Token Ã™â€¦Ã™â€  Ã˜Â§Ã™â€žÃ˜Â®Ã˜Â§Ã˜Â¯Ã™â€¦.
abstract final class FirebaseChatAuth {
  /// Ã™â€¦Ã™â€žÃ˜Â­ Ã˜Â«Ã˜Â§Ã˜Â¨Ã˜Âª Ã™â€žÃ™â€žÃ™â€¦Ã˜Â´Ã˜Â±Ã™Ë†Ã˜Â¹ Ã¢â‚¬â€ Ã˜ÂºÃ™Å Ã™â€˜Ã˜Â±Ã™â€¡ Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â¥Ã˜ÂµÃ˜Â¯Ã˜Â§Ã˜Â±Ã˜Â§Ã˜Âª Ã™Ë†Ã™â€žÃ˜Â§ Ã˜ÂªÃ˜Â±Ã™ÂÃ˜Â¹Ã™â€¡ Ã™Æ’Ã˜Â³Ã˜Â±Ã˜Â§Ã™â€¹ Ã˜Â¹Ã™â€žÃ™â€ Ã™Å Ã˜Â§Ã™â€¹.
  static const String _salt = 'AMMARJO_UNIFIED_CHAT_V1';

  /// Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜ÂªÃ™ÂÃ™Å  Ã˜Â¨Ã™â€¦Ã˜ÂªÃ˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª Firebase (Ã¢â€°Â¥6 Ã˜Â£Ã˜Â­Ã˜Â±Ã™Â) Ã™Ë†Ã™â€¦Ã˜Â³Ã˜ÂªÃ™â€šÃ˜Â±Ã˜Â© Ã™â€žÃ™Æ’Ã™â€ž Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯.
  static String derivedPasswordForEmail(String email) {
    final e = email.trim().toLowerCase();
    final digest = sha256.convert(utf8.encode('$e|$_salt'));
    final b64 = base64Url.encode(digest.bytes);
    return 'Aj${b64.substring(0, 24)}!';
  }

  /// Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã˜Â£Ã™Ë† Ã˜Â¥Ã™â€ Ã˜Â´Ã˜Â§Ã˜Â¡ Ã˜Â­Ã˜Â³Ã˜Â§Ã˜Â¨ Firebase Ã˜Â¨Ã™â€ Ã™ÂÃ˜Â³ Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ Ã˜Â§Ã™â€žÃ™â€¦Ã˜ÂªÃ˜Â¬Ã˜Â± (Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜ÂªÃ™â€šÃ˜Â© Ã™ÂÃ™â€šÃ˜Â· Ã¢â‚¬â€ Ã™â€žÃ˜Â§ JWT).
  static Future<User?> ensureFirebaseUser(String wooEmail) async {
    final email = wooEmail.trim();
    if (email.isEmpty) return null;
    final pwd = derivedPasswordForEmail(email);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      return cred.user;
    } on FirebaseAuthException {
      try {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pwd);
        return cred.user;
      } on Object {
        debugPrint('FirebaseChatAuth createUser failed');
        rethrow;
      }
    }
  }

  /// Ã™â€žÃ™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ™â€¦Ã™Ë†Ã˜Â­Ã™â€˜Ã˜Â¯Ã˜Â©: Ã˜Â¥Ã™â€  Ã™Æ’Ã˜Â§Ã™â€ Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â¬Ã™â€žÃ˜Â³Ã˜Â© Ã˜Â§Ã™â€žÃ˜Â­Ã˜Â§Ã™â€žÃ™Å Ã˜Â© Ã˜Â¨Ã™â€ Ã™ÂÃ˜Â³ Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â±Ã™Å Ã˜Â¯ (Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã˜Â¹) Ã™â€ Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦Ã™â€¡Ã˜Â§ Ã™â€¦Ã˜Â¨Ã˜Â§Ã˜Â´Ã˜Â±Ã˜Â©.
  ///
  /// Ã˜ÂªÃ˜Â¬Ã™â€ Ã™â€˜Ã˜Â¨Ã˜Â§Ã™â€¹ Ã™â€žÃ˜ÂªÃ˜Â¹Ã˜Â§Ã˜Â±Ã˜Â¶ [ensureFirebaseUser] Ã™â€¦Ã˜Â¹ Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦Ã™Å Ã™â€  Ã˜Â§Ã™â€žÃ˜Â°Ã™Å Ã™â€  Ã˜Â³Ã˜Â¬Ã™â€˜Ã™â€žÃ™Ë†Ã˜Â§ Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã˜Â¨Ã™Æ’Ã™â€žÃ™â€¦Ã˜Â© Ã™â€¦Ã˜Â±Ã™Ë†Ã˜Â± Ã˜Â­Ã™â€šÃ™Å Ã™â€šÃ™Å Ã˜Â©
  /// (Ã™ÂÃ˜Â´Ã™â€ž `signInWithEmailAndPassword` Ã˜Â¨Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â´Ã˜ÂªÃ™â€šÃ˜Â© Ã¢â€ â€™ Ã˜Â§Ã™â€žÃ˜Â´Ã˜Â§Ã˜Âª Ã™â€žÃ˜Â§ Ã™Å Ã˜Â¹Ã™â€¦Ã™â€ž Ã˜Â¹Ã™â€žÃ™â€° Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â).
  static Future<User?> ensureFirebaseUserForUnifiedChat(String wooEmail) async {
    final want = wooEmail.trim().toLowerCase();
    if (want.isEmpty) return null;
    final cur = FirebaseAuth.instance.currentUser;
    if (cur != null) {
      final curEmail = cur.email?.trim().toLowerCase() ?? '';
      if (curEmail.isNotEmpty && curEmail == want) {
        return cur;
      }
      for (final p in cur.providerData) {
        final pe = p.email?.trim().toLowerCase() ?? '';
        if (pe.isNotEmpty && pe == want) return cur;
      }
    }
    return ensureFirebaseUser(wooEmail);
  }

  static String? get currentUid => FirebaseAuth.instance.currentUser?.uid;
}


