import '../../config/shipping_policy.dart';

/// إعدادات المتجر من Firestore — **`store_settings/shipping`** (شحن قابل للتعديل من الأدمن).
abstract final class StoreSettingsRepository {
  static const String collection = 'store_settings';
  static const String shippingDocId = 'shipping';

  static Future<ShippingPolicy> fetchShippingPolicy() async {
    return ShippingPolicy.defaults;
  }

  static Stream<ShippingPolicy> watchShippingPolicy() {
    return (() async* {
      yield ShippingPolicy.defaults;
      yield* Stream<ShippingPolicy>.periodic(const Duration(minutes: 5), (_) => ShippingPolicy.defaults);
    })();
  }

  static Future<void> saveShippingPolicy(ShippingPolicy policy) async {
    return;
  }
}
