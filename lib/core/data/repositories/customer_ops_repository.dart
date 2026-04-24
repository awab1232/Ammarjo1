import '../../constants/order_status.dart';
import '../../contracts/feature_state.dart';
import '../../services/backend_orders_client.dart';

class TrackOrderItem {
  TrackOrderItem({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.firebaseOrderId,
    this.storeName,
    this.totalLabel,
    this.items = const <Map<String, dynamic>>[],
    this.trackingUrl,
    this.trackingNumber,
    this.shippingCompany,
    this.estimatedDeliveryDate,
    this.updatedAt,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.pointsAdded = false,
    this.pointsEarned = 0,
    this.driverName,
    this.driverPhone,
    this.etaMinutes,
    this.deliveryStatus,
    this.canRetry,
    this.retryRemaining,
  });

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final String? firebaseOrderId;
  final String? storeName;
  final String? totalLabel;
  final List<Map<String, dynamic>> items;

  /// رابط صفحة التتبع لشركة الشحن (يجب أن يكون http/https).
  final String? trackingUrl;
  final String? trackingNumber;
  final String? shippingCompany;
  final DateTime? estimatedDeliveryDate;
  final DateTime? updatedAt;

  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final bool pointsAdded;
  final int pointsEarned;

  /// Backend delivery (GET /orders, GET /orders/:id merged fields).
  final String? driverName;
  final String? driverPhone;
  final int? etaMinutes;
  final String? deliveryStatus;
  final bool? canRetry;
  final int? retryRemaining;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) throw StateError('unexpected_empty_response');
    try {
      final sec = (value as dynamic).seconds;
      if (sec is int) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    } on Object {
      // Fallback to string parse below for non-timestamp values.
    }
    return DateTime.tryParse(value.toString());
  }

  factory TrackOrderItem.fromMap(String id, Map<String, dynamic> d) {
    var created = DateTime.now();
    final parsedCreated = _parseDate(d['createdAt']);
    if (parsedCreated != null) created = parsedCreated;
    final updated = _parseDate(d['updatedAt']);
    final est = _parseDate(d['estimatedDeliveryDate']);
    final rawItems = d['items'];
    List<Map<String, dynamic>> parsed = List<Map<String, dynamic>>.empty();
    if (rawItems is List) {
      parsed = rawItems.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList();
    }
    double? dLat;
    double? dLng;
    final loc = d['deliveryLocation'];
    if (loc is Map) {
      dLat = (loc['latitude'] as num?)?.toDouble();
      dLng = (loc['longitude'] as num?)?.toDouble();
    }
    return TrackOrderItem(
      id: id,
      title: d['title'] as String? ?? 'طلب',
      status: (d['status'] as String?) ?? 'pending',
      createdAt: created,
      firebaseOrderId: d['firebaseOrderId'] as String?,
      storeName: d['storeName'] as String?,
      totalLabel: d['total'] as String?,
      items: parsed,
      trackingUrl: d['trackingUrl'] as String?,
      trackingNumber: d['trackingNumber'] as String?,
      shippingCompany: d['shippingCompany'] as String?,
      estimatedDeliveryDate: est,
      updatedAt: updated,
      deliveryLatitude: dLat,
      deliveryLongitude: dLng,
      pointsAdded: d['pointsAdded'] == true,
      pointsEarned: (d['pointsEarned'] as num?)?.toInt() ??
          (d['pointsAdded'] == true
              ? (() {
                  final totalRaw = d['total']?.toString() ?? '';
                  final parsed = double.tryParse(totalRaw.replaceAll(RegExp(r'[^0-9.]'), ''));
                  if (parsed == null) throw StateError('INVALID_NUMERIC_DATA');
                  return parsed.floor();
                })()
              : 0),
      driverName: d['driverName']?.toString(),
      driverPhone: d['driverPhone']?.toString(),
      etaMinutes: (d['etaMinutes'] as num?)?.toInt(),
      deliveryStatus: d['deliveryStatus']?.toString(),
      canRetry: d['canRetry'] as bool?,
      retryRemaining: (d['retryRemaining'] as num?)?.toInt(),
    );
  }
}

class WalletTransactionItem {
  WalletTransactionItem({
    required this.id,
    required this.type,
    required this.amount,
    required this.counterpartyEmail,
    required this.createdAt,
    required this.note,
  });

  final String id;
  final String type;
  final double amount;
  final String counterpartyEmail;
  final DateTime createdAt;
  final String note;

  factory WalletTransactionItem.fromMap(String id, Map<String, dynamic> d) {
    var created = DateTime.now();
    final parsed = TrackOrderItem._parseDate(d['createdAt']);
    if (parsed != null) created = parsed;
    return WalletTransactionItem(
      id: id,
      type: d['type'] as String? ?? 'unknown',
      amount: (() {
        final raw = d['amount'];
        final value = (raw as num?)?.toDouble();
        if (value == null) throw StateError('INVALID_NUMERIC_DATA');
        return value;
      })(),
      counterpartyEmail: d['counterpartyEmail'] as String? ?? '',
      createdAt: created,
      note: d['note'] as String? ?? '',
    );
  }
}

class CustomerOpsRepository {
  CustomerOpsRepository._();
  static final CustomerOpsRepository instance = CustomerOpsRepository._();

  static const String ordersSubcollection = 'orders';

  /// حالات WooCommerce → حالة واجهة التتبع في التطبيق.
  static String appStatusFromWoo(String wooStatus) {
    switch (wooStatus) {
      case 'completed':
        return 'delivered';
      case 'processing':
        return 'loading';
      case 'cancelled':
      case 'failed':
      case 'refunded':
        return 'cancelled';
      default:
        return 'pending';
    }
  }

  Future<void> syncOrderToFirestore({
    required String uid,
    required int wooOrderId,
    required String customerEmail,
    required String title,
    required String appStatus,
    required String wooStatus,
    DateTime? createdAt,
    String? orderTotal,
  }) async {}

  /// بيانات لدمجها في `users/{customerUid}/orders/{orderId}` عند تحديث الحالة من لوحة الإدارة
  /// (نفس [appStatusFromWoo] + [OrderStatus.toEnglish] ليتطابق عرض «طلباتي» مع الجدول).
  static Map<String, dynamic> buildUserOrderSyncDataFromAdminStatus({
    required String orderId,
    required String newStatusEnglish,
    required String title,
    String? totalLabel,
    List<dynamic>? items,
    bool? pointsAdded,
    int? pointsEarned,
  }) {
    final en = OrderStatus.toEnglish(newStatusEnglish);
    return <String, dynamic>{
      'firebaseOrderId': orderId,
      'title': title,
      'status': CustomerOpsRepository.appStatusFromWoo(en),
      'wooStatus': en,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (totalLabel != null && totalLabel.isNotEmpty) 'total': totalLabel,
      if (items != null) 'items': items,
      if (pointsAdded != null) 'pointsAdded': pointsAdded,
      if (pointsEarned != null) 'pointsEarned': pointsEarned,
    };
  }

  static Future<void> syncOrderWithCustomer({
    required String orderId,
    required String customerUid,
    required Map<String, dynamic> orderData,
  }) async {}

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
  }) async {}

  Future<bool> cancelFirebaseOrderForCustomer({
    required String uid,
    required String userOrderDocId,
    String? rootOrderId,
  }) async {
    final id = (rootOrderId ?? userOrderDocId).trim();
    if (id.isEmpty) return false;
    return BackendOrdersClient.instance.patchOrderStatus(
      orderId: id,
      statusEnglish: 'cancelled',
    );
  }

  /// طلبات المتجر من **`users/{uid}/orders`** — نفس [uid] المستخدم في [syncOrderToFirestore]
  /// (يُفضَّل `FirebaseAuth.currentUser.uid` عند وجود جلسة).
  /// [limit] يُقيّد الحجم (افتراضي 20) — زِد الحدّ في الواجهة لتحميل المزيد.
  Stream<FeatureState<List<TrackOrderItem>>> watchOrders(String userKey, {int limit = 20}) async* {
    try {
      final rows = await BackendOrdersClient.instance.fetchOrdersForCurrentUser(limit: limit);
      if (rows == null) {
        yield FeatureState.failure('Orders payload is null.');
        return;
      }
      yield FeatureState.success(
        rows
            .map((e) => TrackOrderItem.fromMap(
                  e['orderId']?.toString() ?? e['id']?.toString() ?? '',
                  e,
                ))
            .toList(),
      );
    } on StateError catch (e) {
      final message = e.message.toString();
      if (message.contains('NULL_RESPONSE')) {
        yield FeatureState.failure('يرجى تسجيل الدخول لعرض الطلبات.');
      } else {
        yield FeatureState.failure('Failed to load orders.');
      }
    } on Object {
      yield FeatureState.failure('Failed to load orders.');
    }
  }

  Stream<double> watchWalletBalance(String email) {
    return Stream.periodic(const Duration(seconds: 10), (_) => 0.0);
  }

  Stream<FeatureState<List<WalletTransactionItem>>> watchTransactions(String email) {
    return Stream<FeatureState<List<WalletTransactionItem>>>.value(
      FeatureState.failure('Wallet transactions endpoint is not wired yet.'),
    );
  }

  Future<void> ensureUserWalletDoc(String email) async {}

  Future<void> payTechnician({
    required String customerEmail,
    required String technicianEmail,
    required double amount,
    required String note,
  }) async {}
}

