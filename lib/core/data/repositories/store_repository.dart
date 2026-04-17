import '../../../features/stores/data/stores_repository.dart';
import '../../../features/stores/domain/store_model.dart';
import '../../../features/stores/domain/store_shelf_product.dart';
import '../../contracts/feature_state.dart';
import '../../contracts/feature_unit.dart';

/// Approved stores + store-scoped reads (REST only).
abstract class StoreRepository {
  Future<FeatureState<List<StoreModel>>> fetchApprovedStores({
    String? city,
    String? category,
  });

  Future<FeatureState<StoreDirectoryPage>> fetchApprovedStoresPage({
    String? city,
    String? category,
    int limit,
    String? startAfter,
  });

  Future<FeatureState<List<Map<String, dynamic>>>> fetchPendingRequestsOnce();

  Future<FeatureState<FeatureUnit>> applyForStore(Map<String, dynamic> data);

  Future<FeatureState<FeatureUnit>> approveStoreRequest(
    String requestId,
    Map<String, dynamic> requestData,
    String applicantId, {
    required String reviewedBy,
    String? reviewNote,
  });

  Future<FeatureState<FeatureUnit>> rejectStoreRequest(
    String requestId, {
    required String reviewedBy,
    required String rejectionReason,
    String? reviewNote,
  });

  Future<FeatureState<FeatureUnit>> deleteStore(String storeId);

  Future<FeatureState<StoreModel>> getMyStore(String ownerId);

  Future<FeatureState<List<StoreShelfProduct>>> fetchStoreShelfProducts(String storeId);

  Future<FeatureState<StoreModel>> fetchStoreDocument(String storeId);

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreCategories(String storeId);
}

class RestStoreRepository implements StoreRepository {
  RestStoreRepository._();
  static final RestStoreRepository instance = RestStoreRepository._();

  final StoresRepository _inner = StoresRepository.instance;

  @override
  Future<FeatureState<List<StoreModel>>> fetchApprovedStores({
    String? city,
    String? category,
  }) =>
      _inner.fetchApprovedStores(city: city, category: category);

  @override
  Future<FeatureState<StoreDirectoryPage>> fetchApprovedStoresPage({
    String? city,
    String? category,
    int limit = StoresRepository.pageSize,
    String? startAfter,
  }) =>
      _inner.fetchApprovedStoresPage(city: city, category: category, limit: limit, startAfter: startAfter);

  @override
  Future<FeatureState<List<Map<String, dynamic>>>> fetchPendingRequestsOnce() => _inner.fetchPendingRequestsOnce();

  @override
  Future<FeatureState<FeatureUnit>> applyForStore(Map<String, dynamic> data) => _inner.applyForStore(data);

  @override
  Future<FeatureState<FeatureUnit>> approveStoreRequest(
    String requestId,
    Map<String, dynamic> requestData,
    String applicantId, {
    required String reviewedBy,
    String? reviewNote,
  }) =>
      _inner.approveStoreRequest(
        requestId,
        requestData,
        applicantId,
        reviewedBy: reviewedBy,
        reviewNote: reviewNote,
      );

  @override
  Future<FeatureState<FeatureUnit>> rejectStoreRequest(
    String requestId, {
    required String reviewedBy,
    required String rejectionReason,
    String? reviewNote,
  }) =>
      _inner.rejectStoreRequest(
        requestId,
        reviewedBy: reviewedBy,
        rejectionReason: rejectionReason,
        reviewNote: reviewNote,
      );

  @override
  Future<FeatureState<FeatureUnit>> deleteStore(String storeId) => _inner.deleteStore(storeId);

  @override
  Future<FeatureState<StoreModel>> getMyStore(String ownerId) => _inner.getMyStore(ownerId);

  @override
  Future<FeatureState<List<StoreShelfProduct>>> fetchStoreShelfProducts(String storeId) =>
      _inner.fetchStoreShelfProducts(storeId);

  @override
  Future<FeatureState<StoreModel>> fetchStoreDocument(String storeId) => _inner.fetchStoreById(storeId);

  @override
  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreCategories(String storeId) =>
      _inner.fetchStoreCategoriesMaps(storeId);
}
