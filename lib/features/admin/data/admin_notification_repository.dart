import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/contracts/feature_unit.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/constants/order_status.dart';
import '../../../core/services/backend_orders_client.dart';
import 'models/admin_notification_model.dart';

/// إشعارات المستخدم الحالي — `GET /notifications` (PostgreSQL).
abstract final class AdminNotificationRepository {
  /// يُستدعى من مسارات المتجر/المالك لإشعار المسؤولين (بدون Firestore).
  static Future<FeatureState<FeatureUnit>> addNotification({
    required String message,
    required String type,
    String? referenceId,
  }) async {
    try {
      await BackendOrdersClient.instance.postInternalBroadcastAdmins(
        title: 'إشعار',
        body: message,
        type: type,
        referenceId: referenceId,
      );
      return FeatureState.success(FeatureUnit.value);
    } on Object {
      debugPrint('[AdminNotificationRepository] addNotification failed');
      return FeatureState.failure('Failed to send admin notification.');
    }
  }

  static bool shouldNotifyOrderCancelled(String previousEn, String newStatusRaw) {
    final next = OrderStatus.toEnglish(newStatusRaw);
    return next == 'cancelled' && previousEn != 'cancelled';
  }

  static Future<FeatureState<int>> fetchUnreadCount() async {
    try {
      final body = await BackendOrdersClient.instance.fetchUserNotifications(limit: 200, offset: 0);
      final items = body?['items'];
      if (items is! List) return FeatureState.failure('Notifications payload is invalid.');
      var n = 0;
      for (final e in items) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        if (m['read'] != true) n++;
      }
      return FeatureState.success(n);
    } on Object {
      debugPrint('[AdminNotificationRepository] fetchUnreadCount failed');
      return FeatureState.failure('Failed to load unread notifications.');
    }
  }

  static Future<FeatureState<List<AdminNotification>>> fetchNotifications({int limit = 30, int offset = 0}) async {
    try {
      final body = await BackendOrdersClient.instance.fetchUserNotifications(limit: limit, offset: offset);
      final items = body?['items'];
      if (items is! List) return FeatureState.failure('Notifications payload is invalid.');
      final out = <AdminNotification>[];
      for (final e in items) {
        if (e is! Map) continue;
        out.add(AdminNotification.fromBackendJson(Map<String, dynamic>.from(e)));
      }
      return FeatureState.success(out);
    } on Object {
      debugPrint('[AdminNotificationRepository] fetchNotifications failed');
      return FeatureState.failure('Failed to load notifications.');
    }
  }

  static Future<void> markAsRead(String notificationId) async {
    await BackendOrdersClient.instance.patchNotificationRead(notificationId);
  }

  static Future<FeatureState<FeatureUnit>> markAllAsRead() async {
    final listState = await fetchNotifications(limit: 200, offset: 0);
    if (listState case FeatureFailure(:final message, :final cause)) {
      return FeatureState.failure(message, cause);
    }
    if (listState is! FeatureSuccess<List<AdminNotification>>) {
      return FeatureState.failure('Failed to load notifications before marking as read.');
    }
    for (final n in listState.data) {
      if (!n.isRead) {
        await markAsRead(n.id);
      }
    }
    return FeatureState.success(FeatureUnit.value);
  }
}
