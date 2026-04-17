import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../services/backend_user_client.dart';

/// Ã˜ÂªÃ™â€¡Ã™Å Ã˜Â¦Ã˜Â© FCM Ã™Ë†Ã˜Â­Ã™ÂÃ˜Â¸ Ã˜Â§Ã™â€žÃ˜Â±Ã™â€¦Ã˜Â² Ã˜ÂªÃ˜Â­Ã˜Âª `users/{uid}` (Ã™â€žÃ˜Â§Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã˜Â§Ã™â€¦ Ã˜Â®Ã˜Â§Ã˜Â¯Ã™â€¦ Ã™â€žÃ˜Â§Ã˜Â­Ã™â€šÃ˜Â§Ã™â€¹ Ã˜Â£Ã™Ë† Ã˜Â£Ã˜Â¯Ã™Ë†Ã˜Â§Ã˜Âª Firebase).
abstract final class FcmBootstrap {
  static Future<void> registerIfSignedIn() async {
    if (kIsWeb) {
      return;
    }
    if (Firebase.apps.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.setAutoInitEnabled(true);
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      final token = await messaging.getToken();
      await _saveToken(user.uid, token);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        final u = FirebaseAuth.instance.currentUser?.uid;
        if (u != null) _saveToken(u, t);
      });
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('FcmBootstrap: unexpected error\n$e\n$st');
      }
    }
  }

  static Future<void> _saveToken(String uid, String? token) async {
    if (token == null || token.isEmpty) return;
    await BackendUserClient.instance.patchUser(uid, <String, dynamic>{
      'fcmToken': token,
      'fcmTokenUpdatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

