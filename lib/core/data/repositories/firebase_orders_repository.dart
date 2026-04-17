import 'dart:math' show Random;

import '../../services/backend_orders_client.dart';
import '../../../features/store/domain/models.dart';

/// Compatibility wrapper kept while callers migrate naming.
abstract final class FirebaseOrdersRepository {
  static const String ordersCollection = 'orders';
  static DateTime? lastDlqBatchProcessedAt;
  static String _dlqLockOwnerMemo = '';

  static String get dlqLockOwnerForInstance {
    if (_dlqLockOwnerMemo.isEmpty) {
      _dlqLockOwnerMemo = 'dlq_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';
    }
    return _dlqLockOwnerMemo;
  }

  static Future<String> createOrderFromCart({
    required List<CartItem> cart,
    required double cartSubtotal,
    required double shippingFee,
    Map<String, double>? shippingByStore,
    required double orderTotal,
    String? couponCode,
    double discountAmount = 0,
    List<String> promotionIds = const <String>[],
    required String customerUid,
    required String customerEmail,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String address1,
    required String city,
    required String country,
    double? latitude,
    double? longitude,
  }) async {
    final payload = <String, dynamic>{
      'customerUid': customerUid,
      'customerEmail': customerEmail,
      'billing': <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'address1': address1,
        'city': city,
        'country': country,
      },
      'items': cart
          .map((e) => <String, dynamic>{
                'productId': e.product.id,
                'name': e.product.name,
                'price': (double.tryParse(e.product.price.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0),
                'quantity': e.quantity,
                'storeId': e.storeId,
                'storeName': e.storeName,
              })
          .toList(),
      'cartSubtotal': cartSubtotal,
      'shippingFee': shippingFee,
      'shippingByStore': shippingByStore ?? <String, double>{},
      'orderTotal': orderTotal,
      if (couponCode != null && couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim(),
      if (discountAmount > 0) 'discountAmount': discountAmount,
      if (promotionIds.isNotEmpty) 'promotionIds': promotionIds,
      if (latitude != null && longitude != null) 'deliveryLocation': {'latitude': latitude, 'longitude': longitude},
    };
    final id = await BackendOrdersClient.instance.createOrderPrimary(payload);
    if (id == null || id.trim().isEmpty) {
      return '';
    }
    return id;
  }

  static Future<void> processFailedMirrorDlqBatch() async {
    lastDlqBatchProcessedAt = DateTime.now();
  }
}
