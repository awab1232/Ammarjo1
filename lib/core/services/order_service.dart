import '../../features/store/domain/models.dart';

/// Portable order **business rules** and document shapes for checkout.
/// No Firebase / Firestore — safe to reuse with a REST + PostgreSQL backend later.
///
/// Persistence (transactions, timestamps, notifications) stays in the data layer.
class OrderService {
  OrderService._();
  static final OrderService instance = OrderService._();

  String normalizeCustomerEmail(String email) => email.trim().toLowerCase();

  /// يُستخرج [storeId] مالك المنتج من أسطر السلة.
  String resolveOrderStoreId(List<CartItem> cart) {
    if (cart.isEmpty) return 'ammarjo';
    final ids = cart.map((e) => e.storeId.trim()).where((s) => s.isNotEmpty).toList();
    if (ids.isEmpty) return 'ammarjo';
    final distinct = ids.toSet();
    if (distinct.length == 1) return ids.first;
    return ids.first;
  }

  String nameForWooId(List<CartItem> cart, int wooId) {
    for (final c in cart) {
      if (c.product.id == wooId) return c.product.name;
    }
    return 'المنتج';
  }

  List<Map<String, dynamic>> cartItemsToFirestoreMaps(List<CartItem> cart) {
    return cart
        .map(
          (e) => <String, dynamic>{
            'productId': e.product.id,
            'name': e.product.name,
            'price': e.product.price,
            if (e.selectedVariant != null) 'variantId': e.selectedVariant!.id,
            if (e.selectedVariant != null) 'variantPrice': e.selectedVariant!.price,
            if (e.selectedVariant != null) 'variantOptions': e.selectedVariant!.options.map((x) => x.toJson()).toList(),
            'quantity': e.quantity,
            'images': e.product.images,
            'storeId': e.storeId,
            'storeName': e.storeName,
            'isTender': e.isTender,
            if (e.tenderId != null) 'tenderId': e.tenderId,
            if (e.tenderImageUrl != null) 'tenderImageUrl': e.tenderImageUrl,
          },
        )
        .toList();
  }

  /// Quantities per catalog `wooId` (non-tender lines only) for stock reservation.
  Map<int, int> aggregateQtyByWooId(List<CartItem> cart) {
    final qtyByWooId = <int, int>{};
    for (final item in cart) {
      if (item.isTender) continue;
      qtyByWooId[item.product.id] = (qtyByWooId[item.product.id] ?? 0) + item.quantity;
    }
    return qtyByWooId;
  }

  Map<String, dynamic> buildBilling({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String address1,
    required String city,
    required String country,
  }) {
    return <String, dynamic>{
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'address_1': address1.trim(),
      'city': city.trim(),
      'country': country.trim().isNotEmpty ? country.trim() : 'JO',
    };
  }

  String buildDeliveryAddress({
    required String address1,
    required String city,
    required String country,
  }) {
    return [
      address1.trim(),
      city.trim(),
      country.trim().isNotEmpty ? country.trim() : 'JO',
    ].where((s) => s.isNotEmpty).join(', ');
  }

  String orderListTitle(List<CartItem> cart) {
    final title = cart.isNotEmpty ? cart.first.product.name : 'طلب';
    return cart.length > 1 ? '$title +${cart.length - 1}' : title;
  }

  /// `orders/{orderId}` body — **بدون** حقول الطابع الزمني من الخادم (يضيفها مصدر البيانات).
  Map<String, dynamic> buildRootOrderDocument({
    required String orderId,
    required String? customerUid,
    required String normalizedCustomerEmail,
    required List<CartItem> cart,
    required List<Map<String, dynamic>> items,
    required double cartSubtotal,
    required double shippingFee,
    Map<String, double>? shippingByStore,
    required double orderTotal,
    String? couponCode,
    double discountAmount = 0,
    List<String> promotionIds = const <String>[],
    required Map<String, dynamic> billing,
    required String deliveryAddress,
    double? latitude,
    double? longitude,
  }) {
    final orderStoreId = resolveOrderStoreId(cart);
    final storeDisplayName = cart.isNotEmpty ? cart.first.storeName : 'متجر عمار جو';
    return <String, dynamic>{
      'source': 'app',
      'firebaseOrderId': orderId,
      'customerUid': customerUid,
      'customerEmail': normalizedCustomerEmail,
      'storeId': orderStoreId,
      'storeName': storeDisplayName,
      'status': 'processing',
      'items': items,
      'subtotal': cartSubtotal.toStringAsFixed(3),
      'subtotalNumeric': cartSubtotal,
      'shipping': shippingFee.toStringAsFixed(3),
      'shippingNumeric': shippingFee,
      if (shippingByStore != null && shippingByStore.isNotEmpty) 'shippingByStore': shippingByStore,
      'total': orderTotal.toStringAsFixed(3),
      'totalNumeric': orderTotal,
      'currency': 'JOD',
      'pointsAdded': false,
      if (couponCode != null && couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim().toUpperCase(),
      if (discountAmount > 0) 'discountAmount': discountAmount,
      if (promotionIds.isNotEmpty) 'promotionIds': promotionIds,
      'billing': billing,
      'deliveryAddress': deliveryAddress,
      if (latitude != null && longitude != null)
        'deliveryLocation': <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
        },
    };
  }

  /// نسخة `stores/{storeId}/orders/{orderId}` — بدون طوابع زمنية.
  Map<String, dynamic> buildStoreOrderMirrorDocument({
    required String orderId,
    required String? customerUid,
    required String normalizedCustomerEmail,
    required List<CartItem> cart,
    required List<Map<String, dynamic>> items,
    required double cartSubtotal,
    required double shippingFee,
    Map<String, double>? shippingByStore,
    required double orderTotal,
    String? couponCode,
    double discountAmount = 0,
    List<String> promotionIds = const <String>[],
    required Map<String, dynamic> billing,
    required String deliveryAddress,
    /// `firstName+lastName` أو البريد كما في المنطق السابق.
    required String customerNameField,
    double? latitude,
    double? longitude,
  }) {
    final orderStoreId = resolveOrderStoreId(cart);
    final storeDisplayName = cart.isNotEmpty ? cart.first.storeName : 'متجر عمار جو';
    return <String, dynamic>{
      'orderId': orderId,
      'firebaseOrderId': orderId,
      'source': 'app',
      'customerId': customerUid ?? '',
      'customerUid': customerUid,
      'customerEmail': normalizedCustomerEmail,
      'customerName': customerNameField,
      'storeId': orderStoreId,
      'storeName': storeDisplayName,
      'status': 'قيد المراجعة',
      'items': items,
      'total': orderTotal.toStringAsFixed(3),
      'totalNumeric': orderTotal,
      'pointsAdded': false,
      'subtotal': cartSubtotal.toStringAsFixed(3),
      'shipping': shippingFee.toStringAsFixed(3),
      if (shippingByStore != null && shippingByStore.isNotEmpty) 'shippingByStore': shippingByStore,
      if (couponCode != null && couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim().toUpperCase(),
      if (discountAmount > 0) 'discountAmount': discountAmount,
      if (promotionIds.isNotEmpty) 'promotionIds': promotionIds,
      'billing': billing,
      'deliveryAddress': deliveryAddress,
      if (latitude != null && longitude != null)
        'deliveryLocation': <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
        },
    };
  }

  /// يقرأ حقول المخزون من بيانات منتج الكتالوج ويتحقق من إمكانية البيع.
  void validateStockForLine({
    required List<CartItem> cart,
    required int wooId,
    required int requestedQty,
    required Map<String, dynamic> productData,
  }) {
    final d = productData;
    final st = (d['stockStatus'] ?? d['stock_status'] ?? 'instock').toString().trim().toLowerCase();
    if (st == 'outofstock') {
      throw StateError('المنتج ${nameForWooId(cart, wooId)} غير متوفر بالكمية المطلوبة');
    }
    final stockRaw = d['stock'] ?? d['stock_quantity'];
    final stockVal = stockRaw is num
        ? stockRaw.toInt()
        : int.tryParse(stockRaw?.toString() ?? '') ?? -1;
    if (stockVal >= 0 && stockVal < requestedQty) {
      throw StateError('المنتج ${nameForWooId(cart, wooId)} غير متوفر بالكمية المطلوبة');
    }
  }

  /// تحديث حقول المخزون بعد الخصم (نفس القواعد السابقة في التطبيق).
  Map<String, dynamic> stockUpdateAfterPurchase({
    required Map<String, dynamic> productData,
    required int qtySold,
  }) {
    final d = productData;
    final stockRaw = d['stock'] ?? d['stock_quantity'];
    final stockVal = stockRaw is num
        ? stockRaw.toInt()
        : int.tryParse(stockRaw?.toString() ?? '') ?? -1;
    if (stockVal < 0) {
      return <String, dynamic>{};
    }
    final next = stockVal - qtySold;
    final newStatus = next <= 0 ? 'outofstock' : 'instock';
    return <String, dynamic>{
      'stock': next,
      'stock_quantity': next,
      'stockStatus': newStatus,
      'stock_status': newStatus,
    };
  }

  void assertCouponUsageAllowed(int? limit, int used) {
    if (limit != null && used >= limit) {
      throw StateError('تم استهلاك كود الخصم بالكامل');
    }
  }

  void assertPromotionUsageAllowed(int? limit, int used) {
    if (limit != null && used >= limit) {
      throw StateError('تم استهلاك العرض بالكامل');
    }
  }
}
