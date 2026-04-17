import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../services/backend_notifications_client.dart';
import '../services/notification_service.dart';

/// In-app notifications are backend-owned (NestJS + PostgreSQL).
abstract final class UserNotificationsRepository {
  /// Normalise an email for `firebase_uid_by_email` document keys (lowercased, trimmed).
  static String _normEmail(String email) => email.trim().toLowerCase();

  /// Resolve a Firebase UID from an email via the `firebase_uid_by_email` collection
  /// (falls back to the `users` collection on `email` equality). Returns an empty
  /// string if no mapping is found so callers can safely skip sending.
  static Future<String> resolveUidByEmail(String email) async {
    final key = _normEmail(email);
    if (key.isEmpty) return '';
    final db = FirebaseFirestore.instance;
    try {
      final snap = await db.collection('firebase_uid_by_email').doc(key).get();
      final mapped = snap.data()?['uid']?.toString() ?? '';
      if (mapped.isNotEmpty) return mapped;
    } on Object catch (e) {
      debugPrint('UserNotificationsRepository.resolveUidByEmail map lookup failed: $e');
    }
    try {
      final q = await db.collection('users').where('email', isEqualTo: key).limit(1).get();
      if (q.docs.isEmpty) return '';
      final data = q.docs.first.data();
      final u = (data['uid'] as String?) ?? q.docs.first.id;
      return u;
    } on Object catch (e) {
      debugPrint('UserNotificationsRepository.resolveUidByEmail users fallback failed: $e');
      return '';
    }
  }

  static Future<void> _write(String targetUid, Map<String, dynamic> data) async {
    if (targetUid.isEmpty) return;

    final title = data['title']?.toString() ?? 'AmmarJo';
    final body = data['body']?.toString() ?? '';
    Future<void> sendPush() async {
      final pushData = <String, dynamic>{};
      data.forEach((k, v) {
        if (k == 'title' || k == 'body' || k == 'createdAt') return;
        if (v == null) return;
        pushData[k] = v;
      });
      await NotificationService.sendPushToUser(
        userId: targetUid,
        title: title,
        body: body,
        data: pushData,
      );
    }

    final payload = <String, dynamic>{
      ...data,
      'userId': targetUid,
      'isRead': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await BackendNotificationsClient.instance.sendInternal(payload);
    await sendPush();
  }

  /// إشعار عام إلى `notifications/{userId}/userNotifications` (بدون إنشاء مثيل — كل الدوال هنا static).
  static Future<void> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    String? referenceId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    await _write(uid, {
      'title': title,
      'body': body,
      'type': type,
      if (referenceId != null && referenceId.isNotEmpty) 'referenceId': referenceId,
    });
  }

  /// يحوّل البريد إلى UID عبر `firebase_uid_by_email` ثم يكتب الإشعار (مثلاً للفني حسب البريد وليس معرف وثيقة `technicians`).
  static Future<void> sendNotificationToUserByEmail({
    required String email,
    required String title,
    required String body,
    String type = 'general',
    String? referenceId,
  }) async {
    final normalized = email.trim();
    if (normalized.isEmpty) return;
    final uid = await resolveUidByEmail(normalized);
    if (uid.isEmpty) {
      debugPrint('UserNotificationsRepository.sendNotificationToUserByEmail: no UID for "$normalized"; skipping.');
      return;
    }
    await sendNotificationToUser(
      userId: uid,
      title: title,
      body: body,
      type: type,
      referenceId: referenceId,
    );
  }

  /// إشعار إلى الإداريين (full_admin / support) مع إمكانية تمرير [adminUserId] لتوجيهه لمسؤول محدد.
  static Future<void> sendNotificationToAdmin({
    required String title,
    required String body,
    String type = 'support_chat',
    String? referenceId,
    String? adminUserId,
  }) async {
    final direct = adminUserId?.trim() ?? '';
    if (direct.isNotEmpty) {
      await _write(direct, {
        'title': title,
        'body': body,
        'type': type,
        if (referenceId != null && referenceId.isNotEmpty) 'referenceId': referenceId,
      });
      return;
    }

    await BackendNotificationsClient.instance.sendInternal(<String, dynamic>{
      'title': title,
      'body': body,
      'type': type,
      if (referenceId != null && referenceId.isNotEmpty) 'referenceId': referenceId,
      'broadcast': 'admins',
    });
  }

  /// يُشعر المسؤولين (حسب البريد) + [extraAdminUids].
  static Future<void> notifyAdminsNewOrder({
    required String customerName,
    required String orderTotalLabel,
    List<String> extraAdminEmails = const ['awabaloran@gmail.com'],
  }) async {
    final seen = <String>{};
    for (final em in extraAdminEmails) {
      if (seen.contains(em)) continue;
      seen.add(em);
      await sendNotificationToUserByEmail(
        email: em,
        title: 'طلب جديد في المتجر',
        body: 'طلب جديد من $customerName',
        type: 'new_order',
      );
    }
  }

  static Future<void> notifyUserNewOrder({
    required String storeOwnerUid,
    required String orderTotalLabel,
  }) async {
    if (storeOwnerUid.isEmpty) return;
    await _write(storeOwnerUid, {
      'title': 'طلب جديد! 🛍️',
      'body': 'لديك طلب جديد بقيمة $orderTotalLabel دينار',
      'type': 'new_order',
    });
  }

  /// غلاف واضح: إشعار صاحب المتجر عند إنشاء طلب جديد.
  static Future<void> sendNotificationToStoreOwner({
    required String storeOwnerUid,
    required String orderId,
    required String orderTotalLabel,
  }) async {
    await sendNotificationToUser(
      userId: storeOwnerUid,
      title: 'طلب جديد',
      body: 'لديك طلب جديد #$orderId بقيمة $orderTotalLabel د.أ',
      type: 'new_order',
      referenceId: orderId,
    );
  }

  /// غلاف واضح: إشعار العميل بتغيير حالة الطلب.
  static Future<void> sendNotificationToCustomer({
    required String customerUid,
    required String orderId,
    required String statusLabel,
  }) async {
    await sendNotificationToUser(
      userId: customerUid,
      title: 'تحديث حالة الطلب',
      body: 'تم تحديث حالة طلبك #$orderId إلى $statusLabel',
      type: 'order_status_update',
      referenceId: orderId,
    );
  }

  /// إشعار تاجر الجملة عند استلام طلب جديد.
  static Future<void> sendNotificationToWholesaler({
    required String wholesalerOwnerUid,
    required String orderId,
    required String storeName,
  }) async {
    await sendNotificationToUser(
      userId: wholesalerOwnerUid,
      title: 'طلب جملة جديد',
      body: 'لديك طلب جملة جديد #$orderId من $storeName',
      type: 'wholesale_new_order',
      referenceId: orderId,
    );
  }

  /// إشعار العميل عند تغيير حالة الطلب من لوحة المتجر (يُكتب في `notifications/{uid}/userNotifications`).
  static Future<void> notifyCustomerOrderStatusChange({
    required String customerUid,
    required String orderId,
    required String statusLabel,
    required String storeName,
  }) async {
    if (customerUid.trim().isEmpty) return;
    await _write(customerUid.trim(), {
      'title': 'تحديث حالة الطلب',
      'body': 'طلبك من $storeName: $statusLabel',
      'type': 'order_status',
      'orderId': orderId,
    });
  }

  static Future<void> notifyServiceRequestToTechnician({
    required String technicianEmail,
    required String clientName,
    required String description,
    String? requestId,
    String? chatId,
  }) async {
    final preview = description.trim().length > 80 ? '${description.trim().substring(0, 77)}...' : description.trim();
    final uid = await resolveUidByEmail(technicianEmail);
    if (uid.isEmpty) {
      debugPrint('UserNotificationsRepository.notifyServiceRequestToTechnician: no UID for "$technicianEmail"; skipping.');
      return;
    }
    await _write(uid, {
      'title': 'طلب فني جديد',
      'body': 'لديك طلب فني جديد من $clientName',
      'type': 'service_request',
      'requestPreview': preview,
      if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
      if (chatId != null && chatId.isNotEmpty) 'chatId': chatId,
    });
  }

  static Future<void> notifyUsedMarketSeller({
    required String sellerUid,
    required String buyerName,
    required String productTitle,
  }) async {
    if (sellerUid.isEmpty) return;
    await _write(sellerUid, {
      'title': 'رسالة جديدة على إعلانك 💬',
      'body': '$buyerName مهتم بـ $productTitle',
      'type': 'used_market_message',
    });
  }

  /// بريد المشتري الحالي لعرض الاسم في الإشعار.
  static String? currentUserDisplayName() {
    final u = FirebaseAuth.instance.currentUser;
    return u?.displayName ?? u?.email;
  }

  /// إشعار المسؤولين بمحادثة دعم جديدة.
  static Future<void> notifyAdminsNewSupportChat({
    required String customerName,
    required String preview,
    List<String> extraAdminEmails = const ['awabaloran@gmail.com'],
  }) async {
    final seen = <String>{};
    for (final em in extraAdminEmails) {
      if (seen.contains(em)) continue;
      seen.add(em);
      await sendNotificationToUserByEmail(
        email: em,
        title: 'محادثة دعم جديدة',
        body: '$customerName — $preview',
        type: 'support_chat',
      );
    }
  }
}
