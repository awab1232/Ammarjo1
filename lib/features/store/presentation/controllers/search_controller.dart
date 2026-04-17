import 'package:flutter/foundation.dart';

import '../../../../core/config/backend_orders_config.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/product_repository.dart';
import '../../../../core/network/network_errors.dart';
import '../../domain/models.dart';
import 'store_pagination.dart';

/// Ø¨Ø­Ø« Ø®Ø§Ø¯Ù…ÙŠ ÙÙŠ Ø§Ù„ÙƒØªØ§Ù„ÙˆØ¬.
class SearchController extends ChangeNotifier {
  SearchController();

  /// ÙŠÙØ±Ø¨ÙŽØ· Ù…Ù† [StoreController] Ù„Ù…Ø³Ø­ Ø§Ù„ØªØµÙÙŠØ© Ø¹Ù†Ø¯ Ø¨Ø¯Ø¡ Ø¨Ø­Ø« Ø¬Ø¯ÙŠØ¯ (Ø¨Ø¯ÙˆÙ† Ø§Ø³ØªÙŠØ±Ø§Ø¯ Ø¯Ø§Ø¦Ø±ÙŠ).
  void Function()? onBeforeSearchClearFilters;

  String searchQuery = '';
  List<Product> searchResults = <Product>[];
  bool isSearching = false;
  String? _searchNextCursor;
  bool searchHasMore = false;
  bool isLoadingMoreSearch = false;

  String? errorMessage;

  bool get isSearchMode => searchQuery.trim().isNotEmpty;

  /// Ù†ØªØ§Ø¦Ø¬ Ø§Ù„Ø¹Ø±Ø¶ Ù„Ù„Ø¨Ø­Ø« ÙÙ‚Ø·.
  List<Product> get displayedProducts => searchResults;

  Future<void> performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      clearSearch();
      return;
    }
    if (!BackendOrdersConfig.useBackendProductsReads) {
      errorMessage = 'ÙŠØªØ·Ù„Ø¨ ØªÙØ¹ÙŠÙ„ Ù‚Ø±Ø§Ø¡Ø© Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª Ù…Ù† Ø§Ù„Ø®Ø§Ø¯Ù….';
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
      errorMessage = net.isNotEmpty ? net : 'ØªØ¹Ø°Ù‘Ø± ØªÙ†ÙÙŠØ° Ø§Ù„Ø¨Ø­Ø«.';
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
          errorMessage = errorMessage ?? 'ØªØ¹Ø°Ù‘Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ø²ÙŠØ¯ Ù…Ù† Ù†ØªØ§Ø¦Ø¬ Ø§Ù„Ø¨Ø­Ø«.';
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
