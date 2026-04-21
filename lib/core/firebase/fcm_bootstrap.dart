import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../services/backend_user_client.dart';

/// تهيئة FCM وحفظ رمز الجهاز تحت `users/{uid}` لمزامنة الإشعارات.
abstract final class FcmBootstrap {
  static Future<void> registerIfSignedIn() async {
    if (kIsWeb) {
      return;
    }
    if (Firebase.apps.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[FCM] WARNING: user is null, skip FCM bootstrap');
      return;
    }

    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.setAutoInitEnabled(true);
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[FCM] permission denied');
        return;
      }
      final token = await messaging.getToken();
      debugPrint('FCM TOKEN: $token');
      await _saveToken(user.uid, token);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        debugPrint('FCM TOKEN: $t');
        final u = FirebaseAuth.instance.currentUser?.uid;
        if (u != null) _saveToken(u, t);
      });
    } on Object catch (e, st) {
      debugPrint('FIREBASE ERROR: $e');
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

