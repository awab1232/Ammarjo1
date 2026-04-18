import 'package:flutter/foundation.dart';

import '../../../../core/config/backend_orders_config.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/product_repository.dart';
import '../../../../core/network/network_errors.dart';
import '../../domain/models.dart';
import 'store_pagination.dart';

/// بحث خادمي في الكتالوج.
class SearchController extends ChangeNotifier {
  SearchController();

  /// يُربَط من [StoreController] لمسح التصفية عند بدء بحث جديد (بدون استيراد دائري).
  void Function()? onBeforeSearchClearFilters;

  String searchQuery = '';
  List<Product> searchResults = <Product>[];
  bool isSearching = false;
  String? _searchNextCursor;
  bool searchHasMore = false;
  bool isLoadingMoreSearch = false;

  String? errorMessage;

  bool get isSearchMode => searchQuery.trim().isNotEmpty;

  /// نتائج العرض للبحث فقط.
  List<Product> get displayedProducts => searchResults;

  Future<void> performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      clearSearch();
      return;
    }
    if (!BackendOrdersConfig.useBackendProductsReads) {
      errorMessage = 'يتطلب تفعيل قراءة المنتجات من الخادم.';
      notifyListeners();
      return;
    }
    onBeforeSearchClearFilters?.call();
    searchQuery = q;
    isSearching = true;
    searchResults = <Product>[];
    _searchNextCursor = null;
    searchHasMore = true;
    notifyListeners();
    try {
      final state = await BackendProductRepository.instance.searchProducts(
        q,
        limit: kStoreCatalogPageSize,
      );
      switch (state) {
        case FeatureSuccess(:final data):
          searchResults = data.data;
          _searchNextCursor = data.nextCursor;
          searchHasMore = data.nextCursor != null;
          errorMessage = null;
        case FeatureMissingBackend(:final featureName):
          errorMessage = 'Feature coming soon ($featureName)';
          searchResults = <Product>[];
        case FeatureAdminNotWired(:final featureName):
        case FeatureAdminMissingEndpoint(:final featureName):
          errorMessage = 'Catalog unavailable ($featureName)';
          searchResults = <Product>[];
        case FeatureCriticalPublicDataFailure(:final featureName):
          errorMessage = 'Service temporarily unavailable ($featureName)';
          searchResults = <Product>[];
        case FeatureFailure(:final message):
          errorMessage = message;
          searchResults = <Product>[];
      }
    } on Object {
      final net = networkUserMessage('unexpected error');
      errorMessage = net.isNotEmpty ? net : 'تعذّر تنفيذ البحث.';
      searchResults = <Product>[];
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    searchQuery = '';
    searchResults = <Product>[];
    _searchNextCursor = null;
    searchHasMore = false;
    isSearching = false;
    isLoadingMoreSearch = false;
    notifyListeners();
  }

  void clearSearchSilently() {
    searchQuery = '';
    searchResults = <Product>[];
    _searchNextCursor = null;
    searchHasMore = false;
    isSearching = false;
    isLoadingMoreSearch = false;
    notifyListeners();
  }

  Future<void> loadMoreSearchResults() async {
    if (!searchHasMore || isLoadingMoreSearch) return;
    if (!BackendOrdersConfig.useBackendProductsReads) return;
    if (searchQuery.trim().isEmpty) return;
    if (_searchNextCursor == null) return;
    isLoadingMoreSearch = true;
    notifyListeners();
    try {
      final state = await BackendProductRepository.instance.searchProducts(
        searchQuery,
        limit: kStoreCatalogPageSize,
        cursor: _searchNextCursor,
      );
      switch (state) {
        case FeatureSuccess(:final data):
          searchResults = [...searchResults, ...data.data];
          _searchNextCursor = data.nextCursor;
          searchHasMore = data.nextCursor != null;
        case FeatureMissingBackend():
        case FeatureAdminNotWired():
        case FeatureAdminMissingEndpoint():
        case FeatureCriticalPublicDataFailure():
        case FeatureFailure():
          errorMessage = errorMessage ?? 'تعذّر تحميل المزيد من نتائج البحث.';
      }
    } on Object {
      final net = networkUserMessage('unexpected error');
      if (net.isNotEmpty) {
        errorMessage = net;
      }
    } finally {
      isLoadingMoreSearch = false;
      notifyListeners();
    }
  }
}
