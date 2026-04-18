import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../features/communication/data/unified_chat_repository.dart';
import '../../features/store/domain/models.dart';
import 'fcm_bootstrap.dart';
import 'firebase_chat_auth.dart';
import 'users_repository.dart';

/// بعد تسجيل الدخول: مزامنة وثيقة المستخدم في Firestore + نشر uid للمحادثات + FCM.
///
/// إن وُجدت جلسة Firebase (مثلاً بعد **التحقق بالهاتف**) لا نستدعي [FirebaseChatAuth.ensureFirebaseUser].
/// وإلا نُنشئ حساباً بريدياً مشتقاً للضيف/التوافق مع الطلبات بدون هاتف.
Future<void> syncChatFirebaseIdentity(CustomerProfile? profile) async {
  if (Firebase.apps.isEmpty) return;
  final email = profile?.email.trim() ?? '';
  if (email.isEmpty) return;
  final p = profile;
  if (p == null) return;
  try {
    final existing = FirebaseAuth.instance.currentUser;
    if (existing == null) {
      await FirebaseChatAuth.ensureFirebaseUser(email);
    }
    await UsersRepository.syncUserDocument(p);
    await UnifiedChatRepository.instance.publishCurrentUserUidMapping(email);
    await FcmBootstrap.registerIfSignedIn();
  } on Object {
    if (kDebugMode) {
      debugPrint('syncChatFirebaseIdentity: unexpected error\n$StackTrace.current');
    }
  }
}

