import '../../../core/services/backend_orders_client.dart';
import '../../../core/contracts/feature_state.dart';

final class BackendStoreClient {
  BackendStoreClient._();
  static final BackendStoreClient instance = BackendStoreClient._();

  Future<Map<String, dynamic>?> fetchStoreById(String storeId) {
    return BackendOrdersClient.instance.fetchStoreById(storeId);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStores({int limit = 100, String? category}) async {
    final rows = await BackendOrdersClient.instance.fetchStores(limit: limit, category: category);
    if (rows == null) return FeatureState.failure('Failed to load stores.');
    return FeatureState.success(rows);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreOrders(String storeId, {int limit = 50, String? cursor}) async {
    final body = await BackendOrdersClient.instance.fetchAuthMe();
    if (body == null) return FeatureState.failure('Failed to load store orders auth context.');
    final data = await BackendOrdersClient.instance.fetchOrdersForCurrentUser(limit: limit, cursor: cursor);
    if (data == null) return FeatureState.failure('Failed to load store orders.');
    return FeatureState.success(data);
  }

  Future<Map<String, dynamic>> fetchStoreAnalytics(String storeId) async {
    final rowsState = await fetchStoreOrders(storeId, limit: 200);
    if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
      return <String, dynamic>{
        'totalOrders': 0,
        'deliveredOrders': 0,
        'openOrders': 0,
        'revenue': 0.0,
      };
    }
    final rows = rowsState.data;
    final totalOrders = rows.length;
    final deliveredOrders = rows
        .where((e) => (e['status']?.toString().toLowerCase() ?? '') == 'delivered')
        .length;
    final revenue = rows.fold<double>(
      0,
      (sum, e) => sum + ((e['totalNumeric'] as num?)?.toDouble() ?? 0),
    );
    return <String, dynamic>{
      'totalOrders': totalOrders,
      'deliveredOrders': deliveredOrders,
      'openOrders': totalOrders - deliveredOrders,
      'revenue': revenue,
    };
  }
}
