import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/contracts/feature_contract_registry.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/contracts/feature_unit.dart';
import '../../../core/services/backend_orders_client.dart';
import '../domain/store_model.dart';
import '../domain/store_shelf_product.dart';

/// One page of directory results (stores list / search).
typedef StoreDirectoryPage = ({
  List<StoreModel> stores,
  String? nextCursor,
  bool hasMore,
});

/// متاجر وطلبات الانضمام عبر REST فقط (PostgreSQL).
class StoresRepository {
  StoresRepository._();
  static final StoresRepository instance = StoresRepository._();

  static const int pageSize = 10;
  static const Duration _cacheTtl = Duration(minutes: 3);
  final Map<String, FeatureState<StoreDirectoryPage>> _storesPageCache = <String, FeatureState<StoreDirectoryPage>>{};
  final Map<String, DateTime> _storesPageCacheAt = <String, DateTime>{};

  String _cacheKey({
    String? city,
    String? category,
    required int limit,
    String? startAfter,
  }) =>
      '${city ?? ''}|${category ?? ''}|$limit|${startAfter ?? ''}';

  bool _isFresh(DateTime? ts) =>
      ts != null && DateTime.now().difference(ts) <= _cacheTtl;

  Future<FeatureState<List<StoreModel>>> fetchApprovedStores({
    String? city,
    String? category,
    String? storeTypeId,
  }) async {
    final page = await fetchApprovedStoresPage(
      city: city,
      category: category,
      storeTypeId: storeTypeId,
      limit: 100,
    );
    return switch (page) {
      FeatureSuccess(:final data) => FeatureState.success(data.stores),
      FeatureMissingBackend(:final featureName) => FeatureState.missingBackend(featureName),
      FeatureAdminNotWired(:final featureName) => FeatureState.adminNotWired(featureName),
      FeatureAdminMissingEndpoint(:final featureName) => FeatureState.failure('Unsupported state: $featureName'),
      FeatureCriticalPublicDataFailure(:final featureName, :final cause) =>
        FeatureState.criticalPublicDataFailure(featureName, cause),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
    };
  }

  static bool _storeVisibleForUserCity(StoreModel s, String userCity) {
    final u = userCity.trim();
    if (u.isEmpty || u == 'all') return true;
    final scope = s.sellScope?.trim();
    if (scope == 'all_jordan') return true;
    if (scope == 'city') {
      final sc = s.city?.trim();
      if (sc != null && sc.isNotEmpty) return sc == u;
    }
    return s.cities.contains(u) || s.cities.contains('all') || s.cities.contains('all_jordan');
  }

  /// صفحة متاجر معتمدة (بدون Firestore).
  Future<FeatureState<StoreDirectoryPage>> fetchApprovedStoresPage({
    String? city,
    String? category,
    String? storeTypeId,
    int limit = pageSize,
    String? startAfter,
  }) async {
    final key = _cacheKey(city: city, category: category, limit: limit, startAfter: startAfter);
    final cached = _storesPageCache[key];
    if (cached != null && _isFresh(_storesPageCacheAt[key])) {
      return cached;
    }
    // Home / directory: **public API only** (`GET /stores/public`) — no Firebase, no authed
    // `/stores` (avoids empty list on Android when user is not signed in).
    const int publicFetchLimit = 200;
    List<Map<String, dynamic>> backend;
    try {
      backend = await BackendOrdersClient.instance.fetchStoresPublic(
            category: category,
            limit: publicFetchLimit,
          ) ??
          <Map<String, dynamic>>[];
    } on Object catch (e) {
      debugPrint('[StoresRepository] fetchStoresPublic failed: $e');
      backend = <Map<String, dynamic>>[];
    }
    if (backend.isEmpty) {
      debugPrint('[StoresRepository] fetchStoresPublic returned 0 rows (check API / base URL).');
      // Do not cache empty — allows retry / reload to hit the network again.
      return FeatureState.success((
        stores: <StoreModel>[],
        nextCursor: null,
        hasMore: false,
      ));
    }
    var stores = backend.map(StoreModel.fromBackendMap).toList();
    final now = DateTime.now();
    stores = stores.map((s) {
      if (s.isBoosted && s.boostExpiresAt != null && s.boostExpiresAt!.isBefore(now)) {
        return StoreModel(
          id: s.id,
          ownerId: s.ownerId,
          name: s.name,
          phone: s.phone,
          description: s.description,
          category: s.category,
          sellScope: s.sellScope,
          city: s.city,
          cities: s.cities,
          status: s.status,
          coverImage: s.coverImage,
          logo: s.logo,
          rating: s.rating,
          reviewCount: s.reviewCount,
          createdAt: s.createdAt,
          hasOffers: s.hasOffers,
          hasActivePromotions: s.hasActivePromotions,
          hasDiscountedProducts: s.hasDiscountedProducts,
          freeDelivery: s.freeDelivery,
          isFeatured: s.isFeatured,
          isBoosted: false,
          boostExpiresAt: null,
          storeTypeId: s.storeTypeId,
          storeTypeKey: s.storeTypeKey,
          storeType: s.storeType,
          deliveryTime: s.deliveryTime,
          shippingPolicy: s.shippingPolicy,
          hasOwnDrivers: s.hasOwnDrivers,
          deliveryFee: s.deliveryFee,
          freeDeliveryMinOrder: s.freeDeliveryMinOrder,
          deliveryAreas: s.deliveryAreas,
          openingHours: s.openingHours,
        );
      }
      return s;
    }).toList();
    final sid = storeTypeId?.trim() ?? '';
    if (sid.isNotEmpty) {
      stores = stores.where((s) => (s.storeTypeId ?? '').trim() == sid).toList();
    }
    final userCity = city?.trim() ?? '';
    if (userCity.isNotEmpty && userCity != 'all') {
      stores = stores.where((s) => _storeVisibleForUserCity(s, userCity)).toList();
    }
    stores.sort((a, b) {
      final boostCmp = (b.isBoosted ? 1 : 0).compareTo(a.isBoosted ? 1 : 0);
      if (boostCmp != 0) return boostCmp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    final state = FeatureState.success((
      stores: stores,
      nextCursor: null,
      hasMore: backend.length >= limit,
    ));
    _storesPageCache[key] = state;
    _storesPageCacheAt[key] = DateTime.now();
    return state;
  }

  Future<FeatureState<List<StoreModel>>> searchStoresByText(
    String query, {
    String? city,
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return FeatureState.success(const <StoreModel>[]);
    }
    final hits = await BackendOrdersClient.instance.searchStores(
      query: q,
      hitsPerPage: limit,
      city: city,
    );
    if (hits == null) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.stores);
    }
    var out = hits.map(StoreModel.fromBackendMap).toList();
    final userCity = city?.trim() ?? '';
    if (userCity.isNotEmpty && userCity != 'all') {
      out = out.where((s) => _storeVisibleForUserCity(s, userCity)).toList();
    }
    return FeatureState.success(out);
  }

  Future<FeatureState<FeatureUnit>> applyForStore(Map<String, dynamic> data) async {
    final ok = await BackendOrdersClient.instance.submitStoreApplication(Map<String, dynamic>.from(data));
    if (!ok) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.stores);
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchPendingRequestsOnce() async {
    final rows = await BackendOrdersClient.instance.fetchPendingStores(limit: 200, offset: 0);
    if (rows == null) {
      return FeatureState.failure('Failed to load pending store requests from backend.');
    }
    return FeatureState.success(rows);
  }

  Future<FeatureState<FeatureUnit>> approveStoreRequest(
    String requestId,
    Map<String, dynamic> requestData,
    String applicantId, {
    required String reviewedBy,
    String? reviewNote,
  }) async {
    final res = await BackendOrdersClient.instance.patchStoreStatus(
      storeId: requestId,
      status: 'approved',
    );
    if (res == null) {
      return FeatureState.failure('Failed to approve store request.');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> rejectStoreRequest(
    String requestId, {
    required String reviewedBy,
    required String rejectionReason,
    String? reviewNote,
  }) async {
    final res = await BackendOrdersClient.instance.patchStoreStatus(
      storeId: requestId,
      status: 'rejected',
    );
    if (res == null) {
      return FeatureState.failure('Failed to reject store request.');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteStore(String storeId) async {
    final ok = await BackendOrdersClient.instance.deleteStoreById(storeId);
    if (!ok) {
      return FeatureState.failure('Failed to delete store.');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<StoreModel>> getMyStore(String ownerId) async {
    final backend = await BackendOrdersClient.instance.fetchStores(limit: 100);
    if (backend == null) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.stores);
    }
    for (final row in backend) {
      if ((row['ownerId']?.toString() ?? '') == ownerId) {
        return FeatureState.success(StoreModel.fromBackendMap(row));
      }
    }
    return FeatureState.failure('DATA_NOT_FOUND');
  }

  Future<FeatureState<List<StoreShelfProduct>>> fetchStoreShelfProducts(String storeId) async {
    List<Map<String, dynamic>> items;
    try {
      items = await BackendOrdersClient.instance.fetchProductsByStore(storeId: storeId, limit: 200) ?? <Map<String, dynamic>>[];
    } on Object {
      items = <Map<String, dynamic>>[];
    }
    final catRows = await BackendOrdersClient.instance.fetchStoreCategories(storeId);
    final idToName = <String, String>{};
    if (catRows != null) {
      for (final c in catRows) {
        final id = c['id']?.toString() ?? '';
        if (id.isNotEmpty) idToName[id] = c['name']?.toString() ?? '';
      }
    }
    final out = items.map((row) {
      final cid = row['categoryId']?.toString();
      final shelf = (cid != null && idToName.containsKey(cid)) ? idToName[cid]! : (cid ?? 'عام');
      return StoreShelfProduct.fromBackendRow(storeId, row, shelfCategory: shelf);
    }).toList();
    return FeatureState.success(out);
  }

  Future<FeatureState<StoreModel>> fetchStoreById(String storeId) async {
    final raw = await BackendOrdersClient.instance.fetchStoreById(storeId);
    if (raw == null) {
      return FeatureState.failure('Failed to load store details.');
    }
    return FeatureState.success(StoreModel.fromBackendMap(raw));
  }

  Future<FeatureState<List<StoreModel>>> getStoresBySubCategory(String subCategoryId) async {
    return BackendOrdersClient.instance.fetchStoresBySubCategory(subCategoryId);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreCategoriesMaps(String storeId) async {
    final rows = await BackendOrdersClient.instance.fetchStoreCategories(storeId);
    if (rows == null) {
      return FeatureState.failure('Failed to load store categories.');
    }
    return FeatureState.success(rows);
  }
}
