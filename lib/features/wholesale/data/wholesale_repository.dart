import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/contracts/feature_state.dart';
import '../domain/quantity_price_tier.dart';
import '../domain/wholesale_order_model.dart';
import '../domain/wholesale_product_model.dart';
import '../domain/wholesaler_category_model.dart';
import '../domain/wholesaler_model.dart';

class WholesaleRepository {
  WholesaleRepository._();
  static final WholesaleRepository instance = WholesaleRepository._();

  static const bool _useBackendWholesaleDev = true;
  static bool get useBackendWholesale =>
      _useBackendWholesaleDev || const bool.fromEnvironment('USE_BACKEND_WHOLESALE', defaultValue: true);

  String get _baseUrl => BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('يرجى تسجيل الدخول أولاً');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('تعذر التحقق من هوية المستخدم');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<dynamic> _httpGetJson(String path, {Map<String, String>? query}) async {
    if (!useBackendWholesale) throw StateError('Backend wholesale disabled');
    if (_baseUrl.isEmpty) throw StateError('Backend URL غير مضبوط');
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        throw StateError('انتهت الجلسة، سجل الدخول مجدداً ثم أعد المحاولة.');
      }
      if (res.statusCode == 403) {
        throw StateError('لا تملك صلاحية تنفيذ هذه العملية.');
      }
      throw StateError('فشل تحميل بيانات الجملة (${res.statusCode})');
    }
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> _httpPostJson(String path, Map<String, dynamic> body) async {
    if (!useBackendWholesale) throw StateError('Backend wholesale disabled');
    if (_baseUrl.isEmpty) throw StateError('Backend URL غير مضبوط');
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        throw StateError('انتهت الجلسة، سجل الدخول مجدداً ثم أعد المحاولة.');
      }
      if (res.statusCode == 403) {
        throw StateError('لا تملك صلاحية تنفيذ هذه العملية.');
      }
      throw StateError('فشل تنفيذ العملية (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _httpPatchJson(String path, Map<String, dynamic> body) async {
    if (!useBackendWholesale) throw StateError('Backend wholesale disabled');
    if (_baseUrl.isEmpty) throw StateError('Backend URL غير مضبوط');
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http
        .patch(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        throw StateError('انتهت الجلسة، سجل الدخول مجدداً ثم أعد المحاولة.');
      }
      if (res.statusCode == 403) {
        throw StateError('لا تملك صلاحية تنفيذ هذه العملية.');
      }
      throw StateError('فشل تنفيذ العملية (${res.statusCode})');
    }
    if (res.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<void> _httpDeleteJson(String path) async {
    if (!useBackendWholesale) throw StateError('Backend wholesale disabled');
    if (_baseUrl.isEmpty) throw StateError('Backend URL غير مضبوط');
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        throw StateError('انتهت الجلسة، سجل الدخول مجدداً ثم أعد المحاولة.');
      }
      if (res.statusCode == 403) {
        throw StateError('لا تملك صلاحية تنفيذ هذه العملية.');
      }
      throw StateError('فشل تنفيذ العملية (${res.statusCode})');
    }
  }

  WholesalerModel _storeFromBackend(Map<String, dynamic> m) {
    return WholesalerModel.fromBackendMap(m);
  }

  WholesaleProduct _productFromBackend(Map<String, dynamic> m) {
    final prices = (m['quantityPrices'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((x) {
          final row = Map<String, dynamic>.from(x);
          final priceRaw = row['price'];
          final price = (priceRaw as num?)?.toDouble();
          if (price == null) {
            throw StateError('INVALID_NUMERIC_DATA');
          }
          return QuantityPriceTier(
            minQuantity: (row['minQty'] as num?)?.toInt() ?? (row['minQuantity'] as num?)?.toInt() ?? 1,
            price: price,
          );
        })
        .toList();
    return WholesaleProduct(
      productId: (m['id'] ?? m['productCode'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      name: (m['name'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      imageUrl: (m['imageUrl'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      unit: (m['unit'] ?? (throw StateError('NULL_RESPONSE'))).toString(),
      quantityPrices: prices,
      stock: (m['stock'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA')),
      categoryId: m['categoryId']?.toString(),
      hasVariants: m['hasVariants'] == true || m['has_variants'] == true,
      variants: (m['variants'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((x) => WholesaleVariant.fromMap(Map<String, dynamic>.from(x)))
          .toList(),
    );
  }

  Future<FeatureState<({List<WholesalerModel> items, String? nextCursor})>> getWholesalers({
    int limit = 20,
    String? cursor,
  }) async {
    try {
      final response = await _httpGetJson('/wholesale/stores', query: {
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      });
      if (response is! Map) {
        return FeatureState.failure('INVALID_RESPONSE_FORMAT');
      }
      final map = Map<String, dynamic>.from(response);
      final rawItems = map['items'];
      if (rawItems is! List) {
        return FeatureState.failure('INVALID_RESPONSE_FORMAT');
      }
      final items = rawItems.whereType<Map>().map((x) => _storeFromBackend(Map<String, dynamic>.from(x))).toList();
      return FeatureState.success((items: items, nextCursor: map['nextCursor']?.toString()));
    } on Object {
      return FeatureState.failure('FAILED_TO_LOAD_WHOLESALERS');
    }
  }

  Future<FeatureState<WholesalerModel>> getWholesaler(String id) async {
    final allState = await getWholesalers(limit: 100);
    if (allState is! FeatureSuccess<({List<WholesalerModel> items, String? nextCursor})>) {
      return switch (allState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('FAILED_TO_LOAD_WHOLESALERS'),
      };
    }
    for (final w in allState.data.items) {
      if (w.id == id) return FeatureState.success(w);
    }
    return FeatureState.failure('DATA_NOT_FOUND');
  }

  Future<FeatureState<({List<WholesaleProduct> products, String? nextCursor})>> fetchWholesalerProductsPage(
    String wholesalerId, {
    int limit = 20,
    String? cursor,
  }) async {
    try {
      final response = await _httpGetJson('/wholesale/products', query: {
        'storeId': wholesalerId.trim(),
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      });
      if (response is! Map) {
        return FeatureState.failure('INVALID_RESPONSE_FORMAT');
      }
      final map = Map<String, dynamic>.from(response);
      final rawItems = map['items'];
      if (rawItems is! List) {
        return FeatureState.failure('INVALID_RESPONSE_FORMAT');
      }
      final items = rawItems.whereType<Map>().map((x) => _productFromBackend(Map<String, dynamic>.from(x))).toList();
      return FeatureState.success((products: items, nextCursor: map['nextCursor']?.toString()));
    } on Object {
      return FeatureState.failure('FAILED_TO_LOAD_WHOLESALE_PRODUCTS');
    }
  }

  Future<FeatureState<List<WholesaleProduct>>> getWholesalerProducts(String id) async {
    final pageState = await fetchWholesalerProductsPage(id, limit: 100);
    return switch (pageState) {
      FeatureSuccess(:final data) => FeatureState.success(data.products),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
      _ => FeatureState.failure('FAILED_TO_LOAD_WHOLESALE_PRODUCTS'),
    };
  }

  Future<String> createWholesaleOrder(WholesaleOrderModel order) async {
    final payload = {
      'wholesalerId': order.wholesalerId,
      'storeId': order.storeOwnerId,
      'storeName': order.storeName,
      'commissionRate': 0.08,
      'items': order.items
          .map((x) => {
                'productId': x.productId,
                if (x.variantId != null) 'variantId': x.variantId,
                'name': x.name,
                'unitPrice': x.unitPrice,
                'quantity': x.quantity,
                'total': x.total,
              })
          .toList(),
    };
    final response = await _httpPostJson('/wholesale/orders', payload);
    return (response['id'] ?? (throw StateError('NULL_RESPONSE'))).toString();
  }

  Future<FeatureState<List<WholesaleOrderModel>>> getWholesalerIncomingOrders(
    String wholesalerId, {
    int limit = 30,
    String? cursor,
  }) async {
    final response = await _httpGetJson('/wholesale/orders', query: {
      'wholesalerId': wholesalerId.trim(),
      'limit': '$limit',
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
    });
    final list = ((response is Map ? response['items'] : response) as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((x) => WholesaleOrderModel.fromBackendMap(Map<String, dynamic>.from(x)))
        .toList();
    return FeatureState.success(list);
  }

  Future<FeatureState<List<WholesaleOrderModel>>> getMyWholesaleOrders(
    String storeOwnerId, {
    int limit = 30,
    String? cursor,
  }) async {
    final response = await _httpGetJson('/wholesale/orders', query: {
      'storeId': storeOwnerId,
      'limit': '$limit',
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
    });
    final list = ((response is Map ? response['items'] : response) as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((x) => WholesaleOrderModel.fromBackendMap(Map<String, dynamic>.from(x)))
        .toList();
    return FeatureState.success(list);
  }

  Stream<FeatureState<List<WholesaleOrderModel>>> watchWholesalerIncomingOrders(String wholesalerId) async* {
    try {
      yield await getWholesalerIncomingOrders(wholesalerId);
    } on Object {
      debugPrint('[WholesaleRepository] watchWholesalerIncomingOrders failed.');
      yield FeatureState.failure('Failed to watch wholesaler incoming orders.');
    }
  }

  Future<({List<WholesaleOrderModel> items, String? nextCursor, bool hasMore})> getWholesaleOrdersPage({
    required int limit,
    String? cursor,
    String? wholesalerId,
  }) async {
    final response = await _httpGetJson('/wholesale/orders', query: {
      if (wholesalerId == null) 'storeId':
        FirebaseAuth.instance.currentUser?.uid ?? (throw StateError('NULL_RESPONSE')),
      if ((wholesalerId ?? '').trim().isNotEmpty) 'wholesalerId': wholesalerId!.trim(),
      'limit': '$limit',
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
    });
    final map = response is Map ? Map<String, dynamic>.from(response) : <String, dynamic>{};
    final items = (map['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((x) => WholesaleOrderModel.fromBackendMap(Map<String, dynamic>.from(x)))
        .toList();
    final nextCursor = map['nextCursor']?.toString();
    return (items: items, nextCursor: nextCursor, hasMore: nextCursor != null && nextCursor.isNotEmpty);
  }

  Future<void> updateWholesaleOrderStatus({
    required String orderId,
    required String status,
  }) async {
    await _httpPatchJson('/wholesale/orders/${Uri.encodeComponent(orderId)}/status', {'status': status});
  }

  Future<void> submitWholesalerJoinRequest({
    required String applicantId,
    required String applicantEmail,
    required String applicantPhone,
    required String wholesalerName,
    required String description,
    required String category,
    required String city,
    List<String>? cities,
  }) async {
    await _httpPostJson('/wholesale/join-requests', {
      'applicantId': applicantId,
      'applicantEmail': applicantEmail,
      'applicantPhone': applicantPhone,
      'wholesalerName': wholesalerName,
      'description': description,
      'category': category,
      'city': city,
      'cities': cities ?? <String>[],
    });
  }

  Future<FeatureState<List<WholesalerCategory>>> getWholesalerCategories(String wholesalerId) async {
    final productsState = await getWholesalerProducts(wholesalerId);
    if (productsState is! FeatureSuccess<List<WholesaleProduct>>) {
      return switch (productsState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load wholesaler categories.'),
      };
    }
    final products = productsState.data;
    final seen = <String>{};
    final out = <WholesalerCategory>[];
    for (final p in products) {
      final c = p.categoryId?.trim() ?? (throw StateError('NULL_RESPONSE'));
      if (c.isEmpty || !seen.add(c)) continue;
      out.add(WholesalerCategory(id: c, name: c, order: out.length));
    }
    return FeatureState.success(out);
  }

  Stream<FeatureState<List<WholesalerCategory>>> watchWholesalerCategories(String wholesalerId) async* {
    yield await getWholesalerCategories(wholesalerId);
  }

  Stream<FeatureState<List<WholesaleProduct>>> watchWholesalerProducts(String wholesalerId) async* {
    yield await getWholesalerProducts(wholesalerId);
  }

  Future<void> deleteWholesalerProduct({
    required String wholesalerId,
    required String productId,
  }) async {
    await _httpDeleteJson('/wholesale/products/${Uri.encodeComponent(productId)}');
  }

  String generateTempDocumentId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> upsertWholesalerProduct({
    required String wholesalerId,
    String? productId,
    required WholesaleProduct product,
  }) async {
    final body = <String, dynamic>{
      'storeId': wholesalerId,
      'name': product.name,
      'imageUrl': product.imageUrl,
      'unit': product.unit,
      'stock': product.stock,
      'categoryId': product.categoryId,
      'hasVariants': product.hasVariants,
      'variants': product.variants
          .map((v) => {
                'sku': v.id,
                'price': v.price,
                'stock': v.stock,
                'isDefault': v.isDefault,
                'options': v.options,
              })
          .toList(),
      'quantityPrices': product.quantityPrices
          .map((x) => {'minQty': x.minQuantity, 'price': x.price})
          .toList(),
    };
    if (productId == null || productId.trim().isEmpty) {
      await _httpPostJson('/wholesale/products', body);
      return;
    }
    await _httpPatchJson('/wholesale/products/${Uri.encodeComponent(productId)}', body);
  }

  Future<void> upsertWholesalerCategory({
    required String wholesalerId,
    String? categoryId,
    required String name,
    int order = 0,
  }) async {
    final body = <String, dynamic>{'storeId': wholesalerId, 'name': name, 'order': order};
    if (categoryId == null || categoryId.trim().isEmpty) {
      await _httpPostJson('/wholesale/categories', body);
      return;
    }
    await _httpPatchJson('/wholesale/categories/${Uri.encodeComponent(categoryId)}', body);
  }

  Future<void> deleteWholesalerCategory({
    required String wholesalerId,
    required String categoryId,
  }) async {
    await _httpDeleteJson('/wholesale/categories/${Uri.encodeComponent(categoryId)}');
  }

  Future<FeatureState<WholesalerModel>> getMyWholesalerByOwner(String ownerUid) async {
    final storesState = await getWholesalers(limit: 100);
    if (storesState is! FeatureSuccess<({List<WholesalerModel> items, String? nextCursor})>) {
      return switch (storesState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('FAILED_TO_LOAD_WHOLESALERS'),
      };
    }
    for (final s in storesState.data.items) {
      if (s.ownerId == ownerUid) return FeatureState.success(s);
    }
    return FeatureState.failure('DATA_NOT_FOUND');
  }

  Future<Map<String, dynamic>> fetchUserDocument(String uid) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || uid.trim().isEmpty) return <String, dynamic>{};
    return <String, dynamic>{
      'uid': uid.trim(),
      'email': me.email ?? (throw StateError('NULL_RESPONSE')),
    };
  }

  Future<void> syncWholesaleCartCloud(String userId, List<Map<String, dynamic>> itemMaps) async {
    // deprecated - migrated away from Firebase wholesale cart mirror
    debugPrint('[WholesaleRepository] skip cloud sync for $userId (${itemMaps.length})');
  }

  Future<FeatureState<List<Map<String, dynamic>>>> loadWholesaleCartItemsFromCloud(String userId) async {
    debugPrint('[WholesaleRepository] skip cloud load for $userId');
    return FeatureState.failure('Cloud wholesale cart sync is deprecated.');
  }

  Future<void> clearWholesaleCartCloud(String userId) async {
    debugPrint('[WholesaleRepository] skip cloud clear for $userId');
  }

  // deprecated - migrated to Postgres wholesale tables
  Future<void> setWholesalerMerged(String id, Map<String, dynamic> data) async {
    await _httpPatchJson('/wholesale/stores/${Uri.encodeComponent(id)}', data);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> getWholesaleProductVariants(String productId) async {
    final response = await _httpGetJson('/wholesale/products/${Uri.encodeComponent(productId)}/variants');
    if (response is! Map) return FeatureState.failure('Invalid wholesale variants payload.');
    final items = (response['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
    return FeatureState.success(items);
  }

  Future<void> addWholesaleProductVariant({
    required String productId,
    required Map<String, dynamic> variant,
  }) async {
    await _httpPostJson('/wholesale/products/${Uri.encodeComponent(productId)}/variants', variant);
  }

  Future<void> patchWholesaleVariant({
    required String variantId,
    required Map<String, dynamic> patch,
  }) async {
    await _httpPatchJson('/wholesale/variants/${Uri.encodeComponent(variantId)}', patch);
  }

  Future<void> deleteWholesaleVariant(String variantId) async {
    await _httpDeleteJson('/wholesale/variants/${Uri.encodeComponent(variantId)}');
  }
}

