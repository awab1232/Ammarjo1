import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/firebase_auth_header_provider.dart';

/// Firebase is used for OTP/session identity only.
/// Email/password auth is intentionally disabled in this project.
abstract final class FirebaseChatAuth {
  /// Legacy fallback removed: do NOT sign in Firebase with email/password.
  /// Return current Firebase user only when already authenticated.
  static Future<User?> ensureFirebaseUser(String wooEmail) async {
    final want = wooEmail.trim().toLowerCase();
    if (want.isEmpty) return null;
    final cur = FirebaseAuth.instance.currentUser;
    if (cur == null) return null;
    final curEmail = cur.email?.trim().toLowerCase() ?? '';
    if (curEmail.isNotEmpty && curEmail == want) {
      await FirebaseAuthHeaderProvider.requireIdToken(reason: 'firebase_chat_auth_existing_session');
      return cur;
    }
    for (final p in cur.providerData) {
      final pe = p.email?.trim().toLowerCase() ?? '';
      if (pe.isNotEmpty && pe == want) {
        await FirebaseAuthHeaderProvider.requireIdToken(reason: 'firebase_chat_auth_existing_provider');
        return cur;
      }
    }
    debugPrint('FirebaseChatAuth skipped: no matching Firebase session for $want');
    return null;
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
