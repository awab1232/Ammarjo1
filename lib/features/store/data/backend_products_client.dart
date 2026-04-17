import '../../../core/services/backend_orders_client.dart';
import '../../../core/contracts/feature_state.dart';

final class BackendProductsClient {
  BackendProductsClient._();
  static final BackendProductsClient instance = BackendProductsClient._();

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreProducts(String storeId, {int limit = 100}) async {
    final rows = await BackendOrdersClient.instance.fetchProductsByStore(storeId: storeId, limit: limit);
    if (rows == null) return FeatureState.failure('Failed to load store products.');
    return FeatureState.success(rows);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreCategories(String storeId) async {
    final rows = await BackendOrdersClient.instance.fetchStoreCategories(storeId);
    if (rows == null) return FeatureState.failure('Failed to load store categories.');
    return FeatureState.success(rows);
  }
}
