import '../services/backend_orders_client.dart';

/// إعدادات إشعارات الأعمال — backend only.
abstract final class BusinessNotificationConfig {
  /// يعيد UID مالك المتجر من backend `stores/:id`.
  static Future<String?> resolveStoreOwnerUid(String storeId) async {
    final sid = storeId.trim();
    if (sid.isEmpty || sid == 'ammarjo') return '';
    final data = await BackendOrdersClient.instance.fetchStoreById(sid);
    if (data == null) return '';
    final owner = data['ownerId']?.toString().trim();
    if (owner != null && owner.isNotEmpty) return owner;
    final legacy = data['userId']?.toString().trim();
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return '';
  }
}
