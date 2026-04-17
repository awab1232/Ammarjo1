import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../features/communication/data/unified_chat_repository.dart';
import '../../features/store/domain/models.dart';
import 'fcm_bootstrap.dart';
import 'firebase_chat_auth.dart';
import 'users_repository.dart';

/// Ã˜Â¨Ã˜Â¹Ã˜Â¯ Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž: Ã™â€¦Ã˜Â²Ã˜Â§Ã™â€¦Ã™â€ Ã˜Â© Ã™Ë†Ã˜Â«Ã™Å Ã™â€šÃ˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦ Ã™ÂÃ™Å  Firestore + Ã™â€ Ã˜Â´Ã˜Â± uid Ã™â€žÃ™â€žÃ™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â§Ã˜Âª + FCM.
///
/// Ã˜Â¥Ã™â€  Ã™Ë†Ã™ÂÃ˜Â¬Ã˜Â¯Ã˜Âª Ã˜Â¬Ã™â€žÃ˜Â³Ã˜Â© Firebase (Ã™â€¦Ã˜Â«Ã™â€žÃ˜Â§Ã™â€¹ Ã˜Â¨Ã˜Â¹Ã˜Â¯ **Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã˜Â¨Ã˜Â§Ã™â€žÃ™â€¡Ã˜Â§Ã˜ÂªÃ™Â**) Ã™â€žÃ˜Â§ Ã™â€ Ã˜Â³Ã˜ÂªÃ˜Â¯Ã˜Â¹Ã™Å  [FirebaseChatAuth.ensureFirebaseUser].
/// Ã™Ë†Ã˜Â¥Ã™â€žÃ˜Â§ Ã™â€ Ã™ÂÃ™â€ Ã˜Â´Ã˜Â¦ Ã˜Â­Ã˜Â³Ã˜Â§Ã˜Â¨Ã˜Â§Ã™â€¹ Ã˜Â¨Ã˜Â±Ã™Å Ã˜Â¯Ã™Å Ã˜Â§Ã™â€¹ Ã™â€¦Ã˜Â´Ã˜ÂªÃ™â€šÃ˜Â§Ã™â€¹ Ã™â€žÃ™â€žÃ˜Â¶Ã™Å Ã™Â/Ã˜Â§Ã™â€žÃ˜ÂªÃ™Ë†Ã˜Â§Ã™ÂÃ™â€š Ã™â€¦Ã˜Â¹ Ã˜Â§Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª Ã˜Â¨Ã˜Â¯Ã™Ë†Ã™â€  Ã™â€¡Ã˜Â§Ã˜ÂªÃ™Â.
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

