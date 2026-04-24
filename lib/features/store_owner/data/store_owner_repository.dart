import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/constants/order_status.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/logging/backend_fallback_logger.dart';
import '../../../core/services/backend_orders_client.dart';
import '../../../core/services/firebase_auth_header_provider.dart';
import '../../../core/utils/image_compress.dart';
import 'owner_entity_doc.dart';

typedef OwnerDocList = List<OwnerEntityDoc>;
typedef JsonMapList = List<Map<String, dynamic>>;
typedef StringList = List<String>;

/// نتيجة [getStoreOrdersPage] — ترقيم بالـ cursor من REST فقط.
class StoreOwnerOrdersPageResult {
  const StoreOwnerOrdersPageResult({
    required this.items,
    required this.hasMore,
    this.nextBackendCursor,
  });

  final List<OwnerEntityDoc> items;
  final bool hasMore;
  final String? nextBackendCursor;
}

/// لوحة صاحب المتجر — قراءة وكتابة عبر REST + تخزين الصور فقط على Firebase Storage.
abstract final class StoreOwnerRepository {
  static String get _baseUrl => BackendOrdersConfig.baseUrl.trim();

  static bool get _backendConfigured => _baseUrl.isNotEmpty;

  static bool get storeOrdersUseBackendPagination =>
      BackendOrdersConfig.useBackendOrdersRead && _backendConfigured;

  static bool get enableHybridStoreBuilder =>
      const bool.fromEnvironment('ENABLE_HYBRID_STORE_BUILDER', defaultValue: false);

  static Future<Map<String, String>?> _authHeadersOptional() async {
    try {
      final auth = await FirebaseAuthHeaderProvider.requireAuthHeaders(reason: 'store_owner_headers');
      return <String, String>{...auth, 'Content-Type': 'application/json'};
    } on Object {
      debugPrint('[StoreOwnerRepository] no signed-in user — request degraded');
      return null;
    }
  }

  static Future<dynamic> _httpGetJson(String path) async {
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('store_owner');
      return null;
    }
    final headers = await _authHeadersOptional();
    if (headers == null) return null;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final res = await http.get(uri, headers: headers);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'store_owner_http',
          reason: 'http_${res.statusCode}',
          extra: {'method': 'GET', 'path': path},
        );
        debugPrint('[StoreOwnerRepository] GET $path failed ${res.statusCode}');
        return null;
      }
      if (res.body.trim().isEmpty) return null;
      return jsonDecode(res.body);
    } on Object {
      debugPrint('[StoreOwnerRepository] GET $path error');
      return null;
    }
  }

  static Future<dynamic> _httpPostJson(String path, Map<String, dynamic> body) async {
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('store_owner');
      return null;
    }
    final headers = await _authHeadersOptional();
    if (headers == null) return null;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final res = await http.post(uri, headers: headers, body: jsonEncode(body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'store_owner_http',
          reason: 'http_${res.statusCode}',
          extra: {'method': 'POST', 'path': path},
        );
        debugPrint('[StoreOwnerRepository] POST $path failed ${res.statusCode}');
        return null;
      }
      if (res.body.trim().isEmpty) return null;
      return jsonDecode(res.body);
    } on Object {
      debugPrint('[StoreOwnerRepository] POST $path error');
      return null;
    }
  }

  static Future<dynamic> _httpPatchJson(String path, Map<String, dynamic> body) async {
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('store_owner');
      return null;
    }
    final headers = await _authHeadersOptional();
    if (headers == null) return null;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final res = await http.patch(uri, headers: headers, body: jsonEncode(body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'store_owner_http',
          reason: 'http_${res.statusCode}',
          extra: {'method': 'PATCH', 'path': path},
        );
        debugPrint('[StoreOwnerRepository] PATCH $path failed ${res.statusCode}');
        return null;
      }
      if (res.body.trim().isEmpty) return null;
      return jsonDecode(res.body);
    } on Object {
      debugPrint('[StoreOwnerRepository] PATCH $path error');
      return null;
    }
  }

  static Future<void> _httpDelete(String path) async {
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('store_owner');
      return;
    }
    final headers = await _authHeadersOptional();
    if (headers == null) return;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final res = await http.delete(uri, headers: headers);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'store_owner_http',
          reason: 'http_${res.statusCode}',
          extra: {'method': 'DELETE', 'path': path},
        );
        debugPrint('[StoreOwnerRepository] DELETE $path failed ${res.statusCode}');
      }
    } on Object {
      debugPrint('[StoreOwnerRepository] DELETE $path error');
    }
  }

  static OwnerEntityDoc _ownerDocFromOrderPayload(Map<String, dynamic> raw) {
    final id = raw['orderId']?.toString() ?? '';
    final m = Map<String, dynamic>.from(raw);
    final s = m['status']?.toString() ?? '';
    var ar = OrderStatus.toArabicForDisplay(s);
    if (ar == 'ملغي') ar = 'إلغاء';
    m['status'] = ar;
    return OwnerEntityDoc(id, m);
  }

  static Future<Map<String, String>> _categoryIdToNameMap(String storeId) async {
    final raw = await _httpGetJson('/stores/${storeId.trim()}/categories');
    final items = (raw is Map ? raw['items'] : null) as List? ?? const <dynamic>[];
    final m = <String, String>{};
    for (final e in items) {
      if (e is Map) {
        final id = e['id']?.toString() ?? '';
        final name = e['name']?.toString() ?? '';
        if (id.isNotEmpty) m[id] = name;
      }
    }
    return m;
  }

  static Future<OwnerDocList> _fetchProductsFromBackend(String storeId) async {
    final raw = await _httpGetJson('/stores/${storeId.trim()}/products');
    final items = (raw is Map ? raw['items'] : null) as List? ?? const <dynamic>[];
    final catNames = await _categoryIdToNameMap(storeId);
    final out = <OwnerEntityDoc>[];
    for (final e in items) {
      if (e is! Map) continue;
      final p = Map<String, dynamic>.from(e);
      final id = p['id']?.toString() ?? '';
      final catId = p['categoryId']?.toString();
      final shelf = (catId != null && catNames.containsKey(catId)) ? catNames[catId]! : (catId ?? 'عام');
      final images = p['images'];
      final urls = <String>[];
      if (images is List) {
        for (final x in images) {
          urls.add(x.toString());
        }
      }
      final stock = (p['stock'] as num?)?.toInt() ?? 0;
      final data = <String, dynamic>{
        'name': p['name'],
        'description': p['description'] ?? '',
        'price': p['price'],
        'hasVariants': p['hasVariants'] ?? false,
        'variants': p['variants'] ?? <dynamic>[],
        'image_urls': urls,
        'shelfCategory': shelf,
        'stock': stock,
        'isAvailable': stock > 0,
        'createdAt': p['createdAt'],
        'categoryId': p['categoryId'],
      };
      out.add(OwnerEntityDoc(id, data));
    }
    out.sort((a, b) {
      final ca = a.data()['createdAt']?.toString() ?? '';
      final cb = b.data()['createdAt']?.toString() ?? '';
      return cb.compareTo(ca);
    });
    return out;
  }

  static Future<OwnerDocList> _fetchCategoriesFromBackend(String storeId) async {
    final raw = await _httpGetJson('/stores/${storeId.trim()}/categories');
    final items = (raw is Map ? raw['items'] : null) as List? ?? const <dynamic>[];
    final out = <OwnerEntityDoc>[];
    for (final e in items) {
      if (e is! Map) continue;
      final c = Map<String, dynamic>.from(e);
      final id = c['id']?.toString() ?? '';
      final data = <String, dynamic>{
        'name': c['name'],
        'createdAt': c['createdAt'],
      };
      out.add(OwnerEntityDoc(id, data));
    }
    out.sort((a, b) => (a.data()['name']?.toString() ?? '').compareTo(
          b.data()['name']?.toString() ?? '',
        ));
    return out;
  }

  static Future<OwnerStoreSnapshot> _fetchStoreSnapshotFromBackend(String storeId) async {
    final raw = await _httpGetJson('/stores/${storeId.trim()}');
    if (raw is! Map) {
      return const OwnerStoreSnapshot(exists: false, data: null);
    }
    final m = Map<String, dynamic>.from(raw);
    final data = <String, dynamic>{
      'name': m['name'] ?? '',
      'description': m['description'] ?? '',
      'phone': m['phone']?.toString() ?? '',
      'deliveryTime': '',
      'coverImage': (m['imageUrl'] ?? m['coverImage'] ?? '').toString(),
      'logo': (m['logoUrl'] ?? m['logo'] ?? '').toString(),
      'shippingPolicy': m['shippingPolicy'],
      'hasOwnDrivers': m['hasOwnDrivers'] != false && m['has_own_drivers'] != false,
      'deliveryFee': m['deliveryFee'] ?? m['delivery_fee'],
      'freeDeliveryMinOrder': m['freeDeliveryMinOrder'] ?? m['free_delivery_min_order'],
      'deliveryAreas': m['deliveryAreas'] ?? m['delivery_areas'],
      'status': m['status'] ?? 'approved',
      'category': m['category'],
      'openingHours': m['openingHours'] ?? m['opening_hours'],
    };
    return OwnerStoreSnapshot(exists: true, data: data);
  }

  static Future<StoreOwnerOrdersPageResult> _getStoreOrdersPageBackend(
    String storeId,
    int limit,
    String? cursor,
  ) async {
    final qs =
        'limit=$limit${cursor != null && cursor.isNotEmpty ? '&cursor=${Uri.encodeQueryComponent(cursor)}' : ''}';
    final raw = await _httpGetJson('/stores/${storeId.trim()}/orders?$qs');
    if (raw is! Map) {
      return const StoreOwnerOrdersPageResult(items: <OwnerEntityDoc>[], hasMore: false);
    }
    final itemsRaw = raw['items'] as List? ?? const <dynamic>[];
    final items = <OwnerEntityDoc>[];
    for (final e in itemsRaw) {
      if (e is Map<String, dynamic>) {
        items.add(_ownerDocFromOrderPayload(e));
      } else if (e is Map) {
        items.add(_ownerDocFromOrderPayload(Map<String, dynamic>.from(e)));
      }
    }
    final next = raw['nextCursor']?.toString();
    final hasMore = raw['hasMore'] == true;
    return StoreOwnerOrdersPageResult(
      items: items,
      hasMore: hasMore,
      nextBackendCursor: hasMore ? next : null,
    );
  }

  static Future<OwnerDocList> _fetchAllStoreOrdersForAnalyticsFromBackend(String storeId) async {
    final all = <OwnerEntityDoc>[];
    String? cursor;
    while (true) {
      final page = await _getStoreOrdersPageBackend(storeId, 50, cursor);
      all.addAll(page.items);
      if (!page.hasMore) break;
      final next = page.nextBackendCursor;
      if (next == null || next.isEmpty) break;
      cursor = next;
    }
    return all;
  }

  static Future<StoreCommissionView> _fetchCommissionViewFromBackend(String storeId) async {
    final raw = await _httpGetJson('/stores/${storeId.trim()}/commissions');
    if (raw is! Map) {
      return const StoreCommissionView(
        totalCommission: 0,
        totalPaid: 0,
        balance: 0,
        orderDocs: <OwnerEntityDoc>[],
      );
    }
    final m = Map<String, dynamic>.from(raw);
    final ordersRaw = m['orders'] as List? ?? const <dynamic>[];
    final list = <OwnerEntityDoc>[];
    for (final e in ordersRaw) {
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);
      final oid = row['orderId']?.toString() ?? '';
      final dt = DateTime.tryParse(row['recordedAt']?.toString() ?? '');
      list.add(
        OwnerEntityDoc(oid, <String, dynamic>{
          'orderTotal': row['orderTotal'],
          'commissionAmount': row['commissionAmount'],
          if (dt != null) 'date': dt.toIso8601String(),
        }),
      );
    }
    return StoreCommissionView(
      totalCommission: (m['totalCommission'] as num?)?.toDouble() ?? 0,
      totalPaid: (m['totalPaid'] as num?)?.toDouble() ?? 0,
      balance: (m['balance'] as num?)?.toDouble() ?? 0,
      orderDocs: list,
    );
  }

  static Future<JsonMapList> fetchProductVariants(String productId) async {
    final raw = await _httpGetJson('/products/${productId.trim()}/variants');
    if (raw is! Map) return <Map<String, dynamic>>[];
    return (raw['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
  }

  static Future<Map<String, dynamic>> addProductVariant({
    required String productId,
    required Map<String, dynamic> variant,
  }) async {
    final raw = await _httpPostJson('/products/${productId.trim()}/variants', variant);
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateProductVariant({
    required String variantId,
    required Map<String, dynamic> patch,
  }) async {
    final raw = await _httpPatchJson('/variants/${variantId.trim()}', patch);
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static Future<void> deleteProductVariant(String variantId) async {
    await _httpDelete('/variants/${variantId.trim()}');
  }

  // ——— Public API (Future-only) ———

  static Future<String?> storeIdForCurrentUser() async {
    final me = await BackendOrdersClient.instance.fetchAuthMe();
    final id = me?.storeId?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  static const int maxProductImages = 5;

  static String newStoreProductDocumentId(String storeId) =>
      'p_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  static Future<OwnerDocList> fetchProducts(String storeId) => _fetchProductsFromBackend(storeId);

  static Future<OwnerDocList> fetchCategories(String storeId) => _fetchCategoriesFromBackend(storeId);

  static Future<Set<String>> fetchDistinctProductCategoryNames(String storeId) async {
    final docs = await fetchProducts(storeId);
    final set = <String>{};
    for (final d in docs) {
      final c = d.data()['shelfCategory']?.toString().trim() ?? '';
      if (c.isNotEmpty) set.add(c);
    }
    return set;
  }

  static Future<void> upsertProduct({
    required String storeId,
    String? productId,
    required String name,
    required String description,
    required double price,
    double? discountPrice,
    required List<String> imageUrls,
    required String shelfCategory,
    required int stock,
    required bool isAvailable,
    bool hasVariants = false,
    List<Map<String, dynamic>> variants = const <Map<String, dynamic>>[],
  }) async {
    final catMap = await _categoryIdToNameMap(storeId);
    String? categoryId;
    final want = shelfCategory.trim();
    for (final e in catMap.entries) {
      if (e.value == want) {
        categoryId = e.key;
        break;
      }
    }
    final body = <String, dynamic>{
      'name': name.trim(),
      'price': price,
      if (description.trim().isNotEmpty) 'description': description.trim(),
      if (categoryId != null) 'categoryId': categoryId,
      'images': imageUrls.take(maxProductImages).toList(),
      'stock': stock,
      'hasVariants': hasVariants,
      if (variants.isNotEmpty) 'variants': variants,
    };
    final pid = productId?.trim();
    if (pid != null && pid.isNotEmpty) {
      await _httpPatchJson('/stores/${storeId.trim()}/products/$pid', body);
    } else {
      await _httpPostJson('/stores/${storeId.trim()}/products', body);
    }
  }

  static Future<void> deleteProduct(String storeId, String productId) async {
    await _httpDelete('/stores/${storeId.trim()}/products/${productId.trim()}');
  }

  static Future<StringList> uploadProductImages({
    required String storeId,
    required String productId,
    required List<Uint8List> bytesList,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < bytesList.length; i++) {
      final ref = FirebaseStorage.instance.ref().child('stores/$storeId/products/$productId/img_$i.jpg');
      final data = await compressImageBytes(bytesList[i], quality: 70, minWidth: 800);
      await ref.putData(data, SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  static Future<String> uploadCategoryImage({
    required String storeId,
    required String categoryDocId,
    required Uint8List bytes,
  }) async {
    final ref = FirebaseStorage.instance.ref().child('stores/$storeId/categories/$categoryDocId.jpg');
    final data = await compressImageBytes(bytes, quality: 75, minWidth: 600);
    await ref.putData(data, SettableMetadata(contentType: 'image/jpeg', cacheControl: 'public, max-age=31536000'));
    return ref.getDownloadURL();
  }

  static Future<void> addCategory({
    required String storeId,
    required String name,
    String? imageUrl,
  }) async {
    await _httpPostJson('/stores/${storeId.trim()}/categories', {
      'name': name.trim(),
    });
  }

  static Future<void> addCategoryWithImage({
    required String storeId,
    required String name,
    Uint8List? imageBytes,
  }) async {
    await addCategory(storeId: storeId, name: name);
  }

  static Future<void> updateCategory({
    required String storeId,
    required String docId,
    required String name,
    String? imageUrl,
  }) async {
    await _httpPatchJson('/stores/${storeId.trim()}/categories/${docId.trim()}', {
      'name': name.trim(),
    });
  }

  static Future<void> deleteCategoryAndReassignProducts({
    required String storeId,
    required String categoryDocId,
    required String categoryName,
  }) async {
    final raw = await _httpGetJson('/stores/${storeId.trim()}/products');
    final items = (raw is Map ? raw['items'] : null) as List? ?? const <dynamic>[];
    for (final e in items) {
      if (e is! Map) continue;
      final p = Map<String, dynamic>.from(e);
      if (p['categoryId']?.toString() == categoryDocId) {
        final pid = p['id']?.toString() ?? '';
        if (pid.isNotEmpty) {
          await _httpPatchJson('/stores/${storeId.trim()}/products/$pid', <String, dynamic>{
            'categoryId': null,
          });
        }
      }
    }
    await _httpDelete('/stores/${storeId.trim()}/categories/${categoryDocId.trim()}');
  }

  static Future<OwnerDocList> _fetchOffersFromBackend(String storeId) async {
    final raw = await _httpGetJson('/stores/${storeId.trim()}/offers');
    final items = (raw is Map ? raw['items'] : null) as List? ?? const <dynamic>[];
    final out = <OwnerEntityDoc>[];
    for (final e in items) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['id']?.toString() ?? '';
      final vu = m['validUntil']?.toString();
      final cr = m['createdAt']?.toString();
      final data = <String, dynamic>{
        'title': m['title'],
        'description': m['description'] ?? '',
        'discountPercent': m['discountPercent'],
        'validUntil': vu,
        'imageUrl': m['imageUrl'] ?? '',
        'createdAt': cr,
      };
      out.add(OwnerEntityDoc(id, data));
    }
    out.sort((a, b) {
      final ta = a.data()['createdAt']?.toString() ?? '';
      final tb = b.data()['createdAt']?.toString() ?? '';
      return tb.compareTo(ta);
    });
    return out;
  }

  static Future<OwnerDocList> fetchOffers(String storeId) => _fetchOffersFromBackend(storeId);

  static Future<void> addOffer({
    required String storeId,
    required String title,
    required String description,
    required double discountPercent,
    required DateTime validUntil,
    required String imageUrl,
  }) async {
    await _httpPostJson('/stores/${storeId.trim()}/offers', <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'discountPercent': discountPercent,
      'validUntil': validUntil.toUtc().toIso8601String(),
      'imageUrl': imageUrl.trim(),
    });
  }

  static Future<String> uploadOfferImage({
    required String storeId,
    required Uint8List bytes,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final ref = FirebaseStorage.instance.ref().child('stores/$storeId/offers/$id.jpg');
    final data = await compressImageBytes(bytes, quality: 75, minWidth: 800);
    await ref.putData(data, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  static Future<void> deleteOffer(String storeId, String offerId) async {
    await _httpDelete('/offers/${offerId.trim()}');
  }

  /// Returns the boost requests for a store wrapped in an explicit
  /// [FeatureState] so the caller can differentiate between "backend said no
  /// rows" and "request failed" instead of defaulting to a silent empty list.
  static Future<FeatureState<List<Map<String, dynamic>>>> fetchBoostRequests(
    String storeId,
  ) async {
    try {
      final raw = await _httpGetJson('/stores/${storeId.trim()}/boost-requests');
      if (raw is! Map) {
        return FeatureState.failure('boost_requests_invalid_response');
      }
      final items = raw['items'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      return FeatureState.success(list);
    } on Object catch (e) {
      return FeatureState.failure('fetch_boost_requests_failed', e);
    }
  }

  static Future<Map<String, dynamic>> createBoostRequest({
    required String storeId,
    required String boostType,
    required int durationDays,
  }) async {
    final raw = await _httpPostJson('/stores/${storeId.trim()}/boost-requests', {
      'boostType': boostType.trim(),
      'durationDays': durationDays,
    });
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static Future<StoreOwnerOrdersPageResult> getStoreOrdersPage({
    required String storeId,
    required int limit,
    String? startAfterCursor,
  }) =>
      _getStoreOrdersPageBackend(storeId, limit, startAfterCursor);

  static Future<OwnerDocList> fetchStoreOrdersForAnalytics(String storeId) =>
      _fetchAllStoreOrdersForAnalyticsFromBackend(storeId);

  static Future<StoreCommissionView> fetchStoreCommissions(String storeId) => _fetchCommissionViewFromBackend(storeId);

  static Future<OwnerStoreSnapshot> fetchStoreSnapshot(String storeId) => _fetchStoreSnapshotFromBackend(storeId);

  static Future<void> updateOrderStatus(String storeId, String orderId, String status) async {
    final en = OrderStatus.toEnglish(status);
    await _httpPatchJson('/orders/${orderId.trim()}/status', <String, dynamic>{'status': en});
  }

  static Future<String> uploadStoreCoverImage({
    required String storeId,
    required Uint8List bytes,
  }) async {
    final name = 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref().child('stores/$storeId/branding/$name');
    final data = await compressImageBytes(bytes, quality: 70, minWidth: 1200);
    await ref.putData(data, SettableMetadata(contentType: 'image/jpeg', cacheControl: 'public, max-age=31536000'));
    return ref.getDownloadURL();
  }

  static Future<String> uploadStoreLogoImage({
    required String storeId,
    required Uint8List bytes,
  }) async {
    final name = 'logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref().child('stores/$storeId/branding/$name');
    final data = await compressImageBytes(bytes, quality: 80, minWidth: 512);
    await ref.putData(data, SettableMetadata(contentType: 'image/jpeg', cacheControl: 'public, max-age=31536000'));
    return ref.getDownloadURL();
  }

  static Future<void> updateStoreSettings({
    required String storeId,
    required String name,
    required String description,
    required String phone,
    required String deliveryTime,
    Map<String, dynamic>? shippingPolicy,
    String? coverImageUrl,
    String? logoUrl,
    Map<String, dynamic>? openingHours,
    bool? hasOwnDrivers,
    num? deliveryFee,
    num? freeDeliveryMinOrder,
    List<String>? deliveryAreas,
  }) async {
    await _httpPatchJson('/stores/${storeId.trim()}', <String, dynamic>{
      'name': name.trim(),
      'description': description.trim(),
      if (openingHours != null) 'openingHours': openingHours,
      if (hasOwnDrivers != null) 'hasOwnDrivers': hasOwnDrivers,
      if (deliveryFee != null) 'deliveryFee': deliveryFee,
      if (freeDeliveryMinOrder != null) 'freeDeliveryMinOrder': freeDeliveryMinOrder,
      if (deliveryAreas != null) 'deliveryAreas': deliveryAreas,
    });
  }

  static Future<Map<String, dynamic>?> getHybridStoreBuilder(String storeId) async {
    if (!enableHybridStoreBuilder) return null;
    final raw = await _httpGetJson('/store-builder/${storeId.trim()}');
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  static Future<Map<String, dynamic>?> bootstrapHybridStoreBuilder({
    required String storeId,
  }) async {
    if (!enableHybridStoreBuilder) return null;
    final raw = await _httpPostJson('/store-builder/bootstrap', {
      'storeId': storeId.trim(),
    });
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  static Future<Map<String, dynamic>?> setHybridStoreMode({
    required String storeId,
    required String mode,
  }) async {
    if (!enableHybridStoreBuilder) return null;
    final raw = await _httpPostJson('/store-builder/${storeId.trim()}/mode', {
      'mode': mode,
    });
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  static Future<Map<String, dynamic>?> getHybridSuggestions(String storeId) async {
    if (!enableHybridStoreBuilder) return null;
    final raw = await _httpPostJson('/ai/store/suggestions', {'storeId': storeId.trim()});
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  static Future<Map<String, dynamic>?> addHybridCategory({
    required String storeId,
    required String name,
    String? imageUrl,
    String? parentId,
  }) async {
    if (!enableHybridStoreBuilder) return null;
    final raw = await _httpPostJson('/store-builder/${storeId.trim()}/categories', {
      'name': name.trim(),
      if (imageUrl != null && imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl.trim(),
      if (parentId != null && parentId.trim().isNotEmpty) 'parentId': parentId.trim(),
    });
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  static Future<Map<String, dynamic>?> updateHybridCategory({
    required String storeId,
    required String categoryId,
    String? name,
    String? imageUrl,
  }) async {
    if (!enableHybridStoreBuilder) return null;
    final raw = await _httpPatchJson('/store-builder/${storeId.trim()}/categories/${categoryId.trim()}', {
      if (name != null) 'name': name.trim(),
      if (imageUrl != null) 'imageUrl': imageUrl.trim(),
    });
    if (raw is Map<String, dynamic>) return raw;
    return null;
  }

  static Future<void> deleteHybridCategory({
    required String storeId,
    required String categoryId,
  }) async {
    if (!enableHybridStoreBuilder) return;
    await _httpDelete('/store-builder/${storeId.trim()}/categories/${categoryId.trim()}');
  }

  static Future<void> reorderHybridCategories({
    required String storeId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (!enableHybridStoreBuilder) return;
    await _httpPostJson('/store-builder/${storeId.trim()}/categories/reorder', {'items': items});
  }
}
