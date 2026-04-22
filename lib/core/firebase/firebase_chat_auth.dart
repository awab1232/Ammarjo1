import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/firebase_auth_header_provider.dart';

/// حساب Firebase بريدي مشتق للضيف أو عند عدم وجود جلسة هاتف (كلمة مرور مشتقة محلياً).
///
/// تُستخدم [buyer_id] / [seller_id] في قواعد الأمان. لا تُشارك [appSalt] علناً في إنتاج حقيقي
/// بديل: Custom Token من الخادم.
abstract final class FirebaseChatAuth {
  /// ملح ثابت للمشروع — غيّره في الإصدارات ولا ترفعه كسراً علنياً.
  static const String _salt = 'AMMARJO_UNIFIED_CHAT_V1';

  /// كلمة مرور تفي بمتطلبات Firebase (≥6 أحرف) ومستقرة لكل بريد.
  static String derivedPasswordForEmail(String email) {
    final e = email.trim().toLowerCase();
    final digest = sha256.convert(utf8.encode('$e|$_salt'));
    final b64 = base64Url.encode(digest.bytes);
    return 'Aj${b64.substring(0, 24)}!';
  }

  /// تسجيل الدخول أو إنشاء حساب Firebase بنفس بريد المتجر (كلمة المرور المشتقة فقط — لا JWT).
  static Future<User?> ensureFirebaseUser(String wooEmail) async {
    final email = wooEmail.trim();
    if (email.isEmpty) return null;
    final pwd = derivedPasswordForEmail(email);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      await FirebaseAuthHeaderProvider.requireIdToken(reason: 'firebase_chat_auth_signin');
      return cred.user;
    } on FirebaseAuthException {
      try {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pwd);
        await FirebaseAuthHeaderProvider.requireIdToken(reason: 'firebase_chat_auth_signup');
        return cred.user;
      } on Object {
        debugPrint('FirebaseChatAuth createUser failed');
        rethrow;
      }
    }
  }

  /// للمحادثات الموحّدة: إن كانت الجلسة الحالية بنفس البريد (بعد التطبيق) نستخدمها مباشرة.
  ///
  /// تجنّباً لتعارض [ensureFirebaseUser] مع المستخدمين الذين سجّلوا الدخول بكلمة مرور حقيقية
  /// (فشل `signInWithEmailAndPassword` بالمشتقة → الشات لا يعمل على الهاتف).
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
