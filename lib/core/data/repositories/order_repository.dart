import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;

import '../order_root_snapshot.dart';
import '../../services/backend_orders_client.dart';
import '../../services/backend_order_read_validator.dart';
import '../../contracts/feature_state.dart';
import 'customer_ops_repository.dart';
import '../../../features/store/domain/models.dart';

/// Order creation and tracking — **backend API only** (no Firestore mirror).
abstract class OrderRepository {
  Future<FeatureState<String>> createOrderFromCart({
    required List<CartItem> cart,
    required double cartSubtotal,
    required double shippingFee,
    Map<String, double>? shippingByStore,
    required double orderTotal,
    String? couponCode,
    double discountAmount,
    List<String> promotionIds,
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
  });

  Future<void> syncOrderToFirestore({
    required String uid,
    required int wooOrderId,
    required String customerEmail,
    required String title,
    required String appStatus,
    required String wooStatus,
    DateTime? createdAt,
    String? orderTotal,
  });

  static Map<String, dynamic> buildUserOrderSyncDataFromAdminStatus({
    required String orderId,
    required String newStatusEnglish,
    required String title,
    String? totalLabel,
    List<dynamic>? items,
    bool? pointsAdded,
    int? pointsEarned,
  }) =>
      CustomerOpsRepository.buildUserOrderSyncDataFromAdminStatus(
        orderId: orderId,
        newStatusEnglish: newStatusEnglish,
        title: title,
        totalLabel: totalLabel,
        items: items,
        pointsAdded: pointsAdded,
        pointsEarned: pointsEarned,
      );

  Future<void> syncOrderWithCustomer({
    required String orderId,
    required String customerUid,
    required Map<String, dynamic> orderData,
  });

  Future<void> syncFirebaseOrderSummary({
    required String uid,
    required String orderDocId,
    required String customerEmail,
    required String title,
    required String appStatus,
    required String wooStatus,
    String? orderTotal,
    String? storeName,
    String? storeId,
    List<Map<String, dynamic>>? items,
    bool pointsAdded,
    int? pointsEarned,
  });

  Future<bool> cancelFirebaseOrderForCustomer({
    required String uid,
    required String userOrderDocId,
    String? rootOrderId,
  });

  Stream<FeatureState<List<TrackOrderItem>>> watchOrders(String email, {int limit});

  Stream<double> watchWalletBalance(String email);

  Stream<FeatureState<List<WalletTransactionItem>>> watchTransactions(String email);

  Future<void> ensureUserWalletDoc(String email);

  Future<void> payTechnician({
    required String customerEmail,
    required String technicianEmail,
    required double amount,
    required String note,
  });

  /// Root `orders/{orderId}` for tracking: Firebase snapshot for fast paint when backend primary is on, then backend replaces if GET succeeds (no merge); otherwise Firebase-only.
  Stream<OrderRootSnapshot> watchOrderDocument(String orderId);

  /// One-shot read (same rules as [watchOrderDocument] first tick) — for Future-based UI refresh.
  Future<OrderRootSnapshot> fetchOrderRootSnapshot(String orderId);
}

class BackendOrderRepository implements OrderRepository {
  BackendOrderRepository._();
  static final BackendOrderRepository instance = BackendOrderRepository._();

  double _parseOrderLinePrice(String rawPrice) {
    final normalized = rawPrice.replaceAll(RegExp(r'[^\d.]'), '');
    final parsed = double.tryParse(normalized);
    if (parsed == null) {
      throw StateError('INVALID_NUMERIC_DATA');
    }
    return parsed;
  }

  final CustomerOpsRepository _ops = CustomerOpsRepository.instance;

  void _logJson(Map<String, dynamic> payload) {
    debugPrint(jsonEncode(payload));
  }

  @override
  Future<FeatureState<String>> createOrderFromCart({
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
    final orderId = _generateOrderId();
    final primaryStoreId = cart.isNotEmpty ? cart.first.storeId : null;
    final payload = <String, dynamic>{
      'orderId': orderId,
      'customerUid': customerUid,
      'customerEmail': customerEmail,
      if (primaryStoreId != null && primaryStoreId.isNotEmpty) 'storeId': primaryStoreId,
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
                'productId': '${e.product.id}',
                'name': e.product.name,
                'price': _parseOrderLinePrice(e.product.price),
                'quantity': e.quantity,
                'storeId': e.storeId,
                'storeName': e.storeName,
                if (e.selectedVariant?.id != null && e.selectedVariant!.id.isNotEmpty)
                  'variantId': e.selectedVariant!.id,
              })
          .toList(),
      'subtotalNumeric': cartSubtotal,
      'shippingNumeric': shippingFee,
      'totalNumeric': orderTotal,
      'currency': 'JOD',
      'shippingByStore': shippingByStore ?? <String, double>{},
      if (couponCode != null && couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim(),
      if (discountAmount > 0) 'discountAmount': discountAmount,
      if (promotionIds.isNotEmpty) 'promotionIds': promotionIds,
      if (latitude != null && longitude != null) 'deliveryLocation': {'latitude': latitude, 'longitude': longitude},
    };
    final id = await BackendOrdersClient.instance.createOrderPrimary(payload);
    if (id == null || id.trim().isEmpty) {
      _logJson({'kind': 'backend_create_order_degraded', 'detail': 'empty_id'});
      return FeatureState.failure('Failed to create order.');
    }
    return FeatureState.success(id);
  }

  /// Generates an RFC-4122 v4-like client-side order id used as an idempotency key.
  /// Meets the backend `orderId` requirement (non-empty, <=128 chars).
  String _generateOrderId() {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).toList();
    return '${b.sublist(0, 4).join()}-${b.sublist(4, 6).join()}-${b.sublist(6, 8).join()}-'
        '${b.sublist(8, 10).join()}-${b.sublist(10, 16).join()}';
  }

  @override
  Future<void> syncOrderToFirestore({
    required String uid,
    required int wooOrderId,
    required String customerEmail,
    required String title,
    required String appStatus,
    required String wooStatus,
    DateTime? createdAt,
    String? orderTotal,
  }) =>
      _ops.syncOrderToFirestore(
        uid: uid,
        wooOrderId: wooOrderId,
        customerEmail: customerEmail,
        title: title,
        appStatus: appStatus,
        wooStatus: wooStatus,
        createdAt: createdAt,
        orderTotal: orderTotal,
      );

  @override
  Future<void> syncOrderWithCustomer({
    required String orderId,
    required String customerUid,
    required Map<String, dynamic> orderData,
  }) =>
      CustomerOpsRepository.syncOrderWithCustomer(
        orderId: orderId,
        customerUid: customerUid,
        orderData: orderData,
      );

  @override
  Future<void> syncFirebaseOrderSummary({
    required String uid,
    required String orderDocId,
    required String customerEmail,
    required String title,
    required String appStatus,
    required String wooStatus,
    String? orderTotal,
    String? storeName,
    String? storeId,
    List<Map<String, dynamic>>? items,
    bool pointsAdded = false,
    int? pointsEarned,
  }) =>
      _ops.syncFirebaseOrderSummary(
        uid: uid,
        orderDocId: orderDocId,
        customerEmail: customerEmail,
        title: title,
        appStatus: appStatus,
        wooStatus: wooStatus,
        orderTotal: orderTotal,
        storeName: storeName,
        storeId: storeId,
        items: items,
        pointsAdded: pointsAdded,
        pointsEarned: pointsEarned,
      );

  @override
  Future<bool> cancelFirebaseOrderForCustomer({
    required String uid,
    required String userOrderDocId,
    String? rootOrderId,
  }) =>
      _ops.cancelFirebaseOrderForCustomer(
        uid: uid,
        userOrderDocId: userOrderDocId,
        rootOrderId: rootOrderId,
      );

  @override
  Stream<FeatureState<List<TrackOrderItem>>> watchOrders(String email, {int limit = 20}) async* {
    while (true) {
      final rows = await BackendOrdersClient.instance.fetchOrdersForCurrentUser(limit: limit);
      if (rows != null) {
        yield FeatureState.success(rows.map(_trackOrderFromBackend).toList());
      } else {
        _logJson({
          'kind': 'backend_orders_list_degraded',
          'endpoint': 'GET /users/:id/orders',
        });
        yield FeatureState.failure('Failed to load orders list.');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  @override
  Stream<double> watchWalletBalance(String email) => _ops.watchWalletBalance(email);

  @override
  Stream<FeatureState<List<WalletTransactionItem>>> watchTransactions(String email) =>
      _ops.watchTransactions(email);

  @override
  Future<void> ensureUserWalletDoc(String email) => _ops.ensureUserWalletDoc(email);

  @override
  Future<void> payTechnician({
    required String customerEmail,
    required String technicianEmail,
    required double amount,
    required String note,
  }) =>
      _ops.payTechnician(
        customerEmail: customerEmail,
        technicianEmail: technicianEmail,
        amount: amount,
        note: note,
      );

  @override
  Future<OrderRootSnapshot> fetchOrderRootSnapshot(String orderId) async {
    final raw = await BackendOrdersClient.instance.fetchOrderGet(orderId);
    if (raw != null && _isValidBackendOrderResponse(raw)) {
      final beOrder = BackendOrderReadValidator.backendOrderMap(raw);
      return OrderRootSnapshot(exists: true, data: beOrder);
    }
    _logJson({'kind': 'backend_order_get_degraded', 'orderId': orderId});
    return const OrderRootSnapshot(exists: false, data: null);
  }

  @override
  Stream<OrderRootSnapshot> watchOrderDocument(String orderId) async* {
    while (true) {
      yield await fetchOrderRootSnapshot(orderId);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}

TrackOrderItem _trackOrderFromBackend(Map<String, dynamic> row) {
  final order = row['order'];
  final payload = order is Map ? Map<String, dynamic>.from(order) : row;
  final itemsRaw = payload['items'];
  final items = itemsRaw is List
      ? itemsRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const <Map<String, dynamic>>[];
  final createdRaw = payload['receivedAt'] ?? payload['createdAt'];
  final createdAt = DateTime.tryParse('${createdRaw ?? ''}') ?? DateTime.now();
  final updatedAt = DateTime.tryParse('${payload['updatedAt'] ?? ''}');
  return TrackOrderItem(
    id: '${payload['orderId'] ?? row['id'] ?? ''}',
    title: '${payload['listTitle'] ?? 'طلب'}',
    status: '${payload['status'] ?? 'processing'}',
    createdAt: createdAt,
    firebaseOrderId: payload['firebaseOrderId']?.toString(),
    storeName: payload['storeName']?.toString(),
    totalLabel: payload['totalNumeric']?.toString(),
    items: items,
    trackingUrl: payload['trackingUrl']?.toString(),
    trackingNumber: payload['trackingNumber']?.toString(),
    shippingCompany: payload['shippingCompany']?.toString(),
    estimatedDeliveryDate: DateTime.tryParse('${payload['estimatedDeliveryDate'] ?? ''}'),
    updatedAt: updatedAt,
    deliveryLatitude: (payload['deliveryLocation'] is Map)
        ? ((payload['deliveryLocation'] as Map)['latitude'] as num?)?.toDouble()
        : null,
    deliveryLongitude: (payload['deliveryLocation'] is Map)
        ? ((payload['deliveryLocation'] as Map)['longitude'] as num?)?.toDouble()
        : null,
    pointsAdded: payload['pointsAdded'] == true,
    pointsEarned: (payload['pointsEarned'] as num?)?.toInt() ?? 0,
    driverName: payload['driverName']?.toString(),
    driverPhone: payload['driverPhone']?.toString(),
    etaMinutes: (payload['etaMinutes'] as num?)?.toInt(),
    deliveryStatus: payload['deliveryStatus']?.toString(),
    canRetry: payload['canRetry'] as bool?,
    retryRemaining: (payload['retryRemaining'] as num?)?.toInt(),
  );
}

bool _isValidBackendOrderResponse(Map<String, dynamic> json) {
  final o = BackendOrderReadValidator.backendOrderMap(json);
  return o['items'] is List;
}
