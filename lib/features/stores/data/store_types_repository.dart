import '../../../core/contracts/feature_state.dart';
import '../../../core/services/backend_orders_client.dart';
import '../domain/store_type_model.dart';

class StoreTypesRepository {
  StoreTypesRepository._();
  static final StoreTypesRepository instance = StoreTypesRepository._();

  static const Duration _cacheTtl = Duration(minutes: 5);
  FeatureState<List<StoreTypeModel>>? _cache;
  DateTime? _cacheAt;
  int _cachedVersion = -1;

  bool _isFresh(DateTime? ts) =>
      ts != null && DateTime.now().difference(ts) <= _cacheTtl;

  Future<FeatureState<List<StoreTypeModel>>> fetchActiveStoreTypes({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null && _isFresh(_cacheAt)) {
      final probe = await BackendOrdersClient.instance.fetchStoreTypesVersioned();
      if (probe.version == _cachedVersion) {
        return _cache!;
      }
    }
    final payload = await BackendOrdersClient.instance.fetchStoreTypesVersioned();
    final items = payload.items.map(StoreTypeModel.fromMap).toList();
    final state = FeatureState.success(items);
    _cache = state;
    _cacheAt = DateTime.now();
    _cachedVersion = payload.version;
    return state;
  }

  void invalidate() {
    _cache = null;
    _cacheAt = null;
    _cachedVersion = -1;
  }
}
