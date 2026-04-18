import 'package:flutter/foundation.dart';

import '../../../../core/config/backend_orders_config.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/product_repository.dart';
import '../../../../core/network/network_errors.dart';
import '../../domain/catalog_active_filters.dart';
import '../../domain/models.dart';
import 'store_pagination.dart';

/// تصفية خادمية للمنتجات.
class FilterController extends ChangeNotifier {
  FilterController();

  /// يُربَط من [StoreController] لمسح البحث عند تطبيق تصفية.
  void Function()? onBeforeApplyClearSearch;

  CatalogActiveFilters? activeFilters;
  List<Product> filteredProducts = <Product>[];
  String? _filterNextCursor;
  bool filterHasMore = false;
  bool isLoadingMoreFilter = false;
  bool isApplyingFilters = false;

  String? errorMessage;

  bool get isFilterMode => activeFilters != null;

  List<Product> get displayedProducts => filteredProducts;

  void clearFiltersSilently() {
    activeFilters = null;
    filteredProducts = <Product>[];
    _filterNextCursor = null;
    filterHasMore = false;
    isApplyingFilters = false;
    notifyListeners();
  }

  Future<void> applyFilters(CatalogActiveFilters filters) async {
    if (!BackendOrdersConfig.useBackendProductsReads) return;
    onBeforeApplyClearSearch?.call();
    activeFilters = filters;
    isApplyingFilters = true;
    filteredProducts = <Product>[];
    _filterNextCursor = null;
    filterHasMore = true;
    notifyListeners();
    try {
      final state = await BackendProductRepository.instance.filterProducts(
        minPrice: filters.minPrice,
        maxPrice: filters.maxPrice,
        categoryWooId: filters.categoryWooId,
        limit: kStoreCatalogPageSize,
      );
      switch (state) {
        case FeatureSuccess(:final data):
          filteredProducts = data.data;
          _filterNextCursor = data.nextCursor;
          filterHasMore = data.nextCursor != null;
          errorMessage = null;
        case FeatureMissingBackend(:final featureName):
          errorMessage = 'Feature coming soon ($featureName)';
        case FeatureAdminNotWired(:final featureName):
        case FeatureAdminMissingEndpoint(:final featureName):
          errorMessage = 'Catalog unavailable ($featureName)';
        case FeatureCriticalPublicDataFailure(:final featureName):
          errorMessage = 'Service temporarily unavailable ($featureName)';
        case FeatureFailure(:final message):
          errorMessage = message;
      }
    } on Object {
      final net = networkUserMessage('unexpected error');
      errorMessage = net.isNotEmpty ? net : 'تعذّر تطبيق التصفية.';
    } finally {
      isApplyingFilters = false;
      notifyListeners();
    }
  }

  Future<void> clearFilters() async {
    activeFilters = null;
    filteredProducts = <Product>[];
    _filterNextCursor = null;
    filterHasMore = false;
    isApplyingFilters = false;
    notifyListeners();
  }

  Future<void> loadMoreFilterResults() async {
    if (!filterHasMore || isLoadingMoreFilter) return;
    if (!BackendOrdersConfig.useBackendProductsReads) return;
    if (activeFilters == null) return;
    if (_filterNextCursor == null) return;
    isLoadingMoreFilter = true;
    notifyListeners();
    try {
      final f = activeFilters!;
      final state = await BackendProductRepository.instance.filterProducts(
        minPrice: f.minPrice,
        maxPrice: f.maxPrice,
        categoryWooId: f.categoryWooId,
        limit: kStoreCatalogPageSize,
        cursor: _filterNextCursor,
      );
      switch (state) {
        case FeatureSuccess(:final data):
          filteredProducts = [...filteredProducts, ...data.data];
          _filterNextCursor = data.nextCursor;
          filterHasMore = data.nextCursor != null;
        case FeatureMissingBackend():
        case FeatureAdminNotWired():
        case FeatureAdminMissingEndpoint():
        case FeatureCriticalPublicDataFailure():
        case FeatureFailure():
          errorMessage = errorMessage ?? 'تعذّر تحميل المزيد.';
      }
    } on Object {
      final net = networkUserMessage('unexpected error');
      if (net.isNotEmpty) {
        errorMessage = net;
      }
    } finally {
      isLoadingMoreFilter = false;
      notifyListeners();
    }
  }
}
