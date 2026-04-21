import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

abstract final class NotificationService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static Future<void> sendPushToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) async {
    if (userId.trim().isEmpty) return;
    try {
      await _functions.httpsCallable('sendPushNotification').call({
        'userId': userId.trim(),
        'title': title,
        'body': body,
        'notificationData': _stringifyData(data),
      });
    } on Object catch (e, st) {
      debugPrint('FIREBASE ERROR: $e');
      debugPrint('NotificationService.sendPushToUser error: unexpected error\n$st');
    }
  }

  static Map<String, String> _stringifyData(Map<String, dynamic> data) {
    final out = <String, String>{};
    data.forEach((key, value) {
      if (key.trim().isEmpty || value == null) return;
      out[key] = value.toString();
    });
    return out;
  }
}

