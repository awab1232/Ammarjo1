import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/chat_feature_config.dart';
import '../services/backend_notifications_client.dart';
import '../contracts/feature_state.dart';

abstract final class LocalChatNotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static final ValueNotifier<int> unreadBadgeCount = ValueNotifier<int>(0);
  static final Set<String> _processedEventIds = <String>{};
  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<RemoteMessage>? _fcmSub;
  static Timer? _webPollTimer;
  static DateTime _lastPollAt = DateTime.now().toUtc().subtract(const Duration(seconds: 5));
  static bool _initialized = false;

  static Future<void> init() async {
    if (!kChatFeatureEnabled) return;
    if (_initialized) return;
    _initialized = true;
    if (!kIsWeb) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _local.initialize(initSettings);
    }
    _bindFcmForegroundNotifications();
  }

  static void bindAuthState() {
    if (!kChatFeatureEnabled) return;
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((u) {
      _webPollTimer?.cancel();
      _processedEventIds.clear();
      unreadBadgeCount.value = 0;
      if (u == null) return;
      if (kIsWeb) {
        _startWebPolling();
      }
    });
  }

  static void _bindFcmForegroundNotifications() {
    _fcmSub?.cancel();
    _fcmSub = FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;
      final eventId = (data['event_id'] ?? data['eventId'] ?? '').toString().trim();
      if (eventId.isNotEmpty && _processedEventIds.contains(eventId)) return;
      if (eventId.isNotEmpty) _processedEventIds.add(eventId);
      final isChatLike =
          (data['type']?.toString().contains('message') ?? false) ||
          data.containsKey('conversationId');
      if (!isChatLike) return;
      unreadBadgeCount.value = unreadBadgeCount.value + 1;
      await _showLocalNotification(
        title: message.notification?.title ?? 'رسالة جديدة',
        body: message.notification?.body ?? 'لديك رسالة جديدة',
      );
    });
  }

  static void _startWebPolling() {
    _webPollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      final state = await BackendNotificationsClient.instance.fetchUpdates(since: _lastPollAt, limit: 20);
      _lastPollAt = DateTime.now().toUtc();
      if (state is! FeatureSuccess<Map<String, dynamic>>) return;
      final body = state.data;
      final unread = int.tryParse('${body['unread'] ?? 0}') ?? 0;
      unreadBadgeCount.value = unread;
      final items = body['items'];
      if (items is! List) return;
      for (final raw in items) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final eventId = (map['eventId'] ?? map['event_id'] ?? '').toString().trim();
        if (eventId.isNotEmpty && _processedEventIds.contains(eventId)) continue;
        if (eventId.isNotEmpty) _processedEventIds.add(eventId);
        final title = (map['title'] ?? 'إشعار جديد').toString();
        final bodyText = (map['body'] ?? '').toString();
        await _showLocalNotification(title: title, body: bodyText);
      }
    });
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    const android = AndroidNotificationDetails(
      'chat_notifications',
      'Chat Notifications',
      channelDescription: 'Realtime chat and inbox notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const details = NotificationDetails(android: android);
    await _local.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }
}
