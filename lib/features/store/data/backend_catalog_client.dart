import '../../../core/services/backend_orders_client.dart';
import '../../../core/contracts/feature_state.dart';

final class BackendCatalogClient {
  BackendCatalogClient._();
  static final BackendCatalogClient instance = BackendCatalogClient._();

  Future<FeatureState<List<Map<String, dynamic>>>> fetchProducts({int limit = 100}) async {
    final stores = await BackendOrdersClient.instance.fetchStores(limit: 100);
    if (stores == null) return FeatureState.failure('Failed to load stores for catalog products.');
    final out = <Map<String, dynamic>>[];
    for (final s in stores) {
      final sid = s['id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      final rows = await BackendOrdersClient.instance.fetchProductsByStore(storeId: sid, limit: limit);
      if (rows != null) out.addAll(rows);
      if (out.length >= limit) break;
    }
    return FeatureState.success(out.take(limit).toList());
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchCategories() async {
    final stores = await BackendOrdersClient.instance.fetchStores(limit: 100);
    if (stores == null) return FeatureState.failure('Failed to load stores for catalog categories.');
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final s in stores) {
      final sid = s['id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      final rows = await BackendOrdersClient.instance.fetchStoreCategories(sid);
      if (rows == null) continue;
      for (final c in rows) {
        final key = c['id']?.toString() ?? '';
        if (key.isNotEmpty && seen.add(key)) out.add(c);
      }
    }
    return FeatureState.success(out);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> searchProducts(String q) async {
    final hits = await BackendOrdersClient.instance.searchProducts(query: q, hitsPerPage: 30, page: 0);
    if (hits == null) return FeatureState.failure('Failed to search products.');
    return FeatureState.success(hits);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchBanners() async {
    return FeatureState.failure('Catalog banners endpoint is not wired.');
  }
}
