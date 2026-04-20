import '../../../core/services/backend_orders_client.dart';
import '../../../core/contracts/feature_state.dart';

final class BackendProductsClient {
  BackendProductsClient._();
  static final BackendProductsClient instance = BackendProductsClient._();

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreProducts(String storeId, {int limit = 100}) async {
    try {
      final rows = await BackendOrdersClient.instance.fetchProductsByStore(storeId: storeId, limit: limit) ?? <Map<String, dynamic>>[];
      return FeatureState.success(rows);
    } on Object {
      return FeatureState.success(const <Map<String, dynamic>>[]);
    }
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreCategories(String storeId) async {
    final rows = await BackendOrdersClient.instance.fetchStoreCategories(storeId);
    if (rows == null) return FeatureState.failure('Failed to load store categories.');
    return FeatureState.success(rows);
  }
}
