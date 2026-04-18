import '../../../features/store/domain/models.dart';
import '../../../features/store/domain/wp_home_banner.dart';
import '../../contracts/feature_contract_registry.dart';
import '../../contracts/feature_state.dart';
import '../../contracts/feature_unit.dart';
import '../../data/models/paginated_response.dart';
import '../../services/backend_orders_client.dart';
import '../../services/product_service.dart';

Product _productFromSearchHit(Map<String, dynamic> hit) {
  final priceRaw = hit['price_numeric'];
  final priceText = priceRaw == null ? '0' : priceRaw.toString();
  final stockStatus = (hit['stockStatus']?.toString().trim().toLowerCase() ??
      (throw StateError('NULL_RESPONSE')));
  return Product(
    id: (hit['productId']?.toString() ??
            hit['objectID']?.toString() ??
            (throw StateError('NULL_RESPONSE')))
        .hashCode
        .abs(),
    name: hit['name']?.toString() ?? (throw StateError('NULL_RESPONSE')),
    description: hit['description']?.toString() ?? (throw StateError('NULL_RESPONSE')),
    price: priceText,
    images: <String>[
      if ((hit['imageUrl']?.toString() ?? (throw StateError('NULL_RESPONSE'))).isNotEmpty)
        hit['imageUrl'].toString(),
    ],
    categoryIds: const <int>[],
    categoryField: hit['storeId']?.toString(),
    stock: stockStatus == 'outofstock' ? 0 : 1,
    stockStatus: stockStatus,
  );
}

Product _productFromBackendRow(Map<String, dynamic> row) {
  final prices = (row['quantityPrices'] as List?) ?? (throw StateError('NULL_RESPONSE'));
  final firstPrice = prices.isNotEmpty && prices.first is Map
      ? ((prices.first as Map)['price']?.toString() ?? (throw StateError('NULL_RESPONSE')))
      : '';
  final stock = (row['stock'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA'));
  final legacy = (row['productCode']?.toString() ?? (throw StateError('NULL_RESPONSE'))).trim();
  final idHash = legacy.isNotEmpty
      ? legacy.hashCode.abs()
      : (row['id']?.toString() ?? (throw StateError('NULL_RESPONSE'))).hashCode.abs();
  return Product(
    id: idHash,
    name: row['name']?.toString() ?? (throw StateError('NULL_RESPONSE')),
    description: row['description']?.toString() ?? (throw StateError('NULL_RESPONSE')),
    price: firstPrice.isEmpty
        ? (row['price']?.toString() ?? (throw StateError('NULL_RESPONSE')))
        : firstPrice,
    images: <String>[
      if ((row['imageUrl']?.toString() ?? (throw StateError('NULL_RESPONSE'))).isNotEmpty)
        row['imageUrl'].toString(),
    ],
    categoryIds: const <int>[],
    categoryField: row['categoryId']?.toString(),
    stock: stock,
    stockStatus: stock > 0 ? 'instock' : 'outofstock',
  );
}

ProductCategory _categoryFromBackendRow(Map<String, dynamic> row) {
  final idText = row['id']?.toString().trim() ?? '';
  final nameText = row['name']?.toString().trim() ?? '';
  final imageText = row['imageUrl']?.toString().trim() ?? row['image']?.toString().trim() ?? '';
  final parentNum = (row['parent'] as num?)?.toInt() ?? 0;
  return ProductCategory(
    id: (idText.isNotEmpty ? idText : nameText).hashCode.abs(),
    name: nameText.isNotEmpty ? nameText : 'قسم',
    imageUrl: imageText,
    parent: parentNum,
    categoryPage: 'stores',
  );
}

const String _kBannerPlaceholderImage = 'https://via.placeholder.com/600x200';

WpHomeBannerSlide _bannerFromBackendRow(Map<String, dynamic> row) {
  final imageUrl = (row['imageUrl'] ?? row['image'])?.toString().trim() ?? '';
  final rawTitle = row['title']?.toString().trim();
  final title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : 'عرض خاص';
  return WpHomeBannerSlide(
    imageUrl: imageUrl.isNotEmpty ? imageUrl : _kBannerPlaceholderImage,
    linkUrl: row['linkUrl']?.toString() ?? row['link']?.toString(),
    title: title,
  );
}

/// Global catalog reads (Algolia + PostgreSQL via orders API only).
abstract class ProductRepository {
  Future<FeatureState<List<ProductCategory>>> fetchAllCategories();
  Future<FeatureState<Product?>> fetchProductByWooId(int wooId);
  Future<FeatureState<List<WpHomeBannerSlide>>> fetchHomeBanners({bool forceRefresh = false});
  Future<FeatureState<PaginatedResponse<Product>>> searchProducts(
    String query, {
    int limit,
    String? cursor,
  });
  Future<FeatureState<PaginatedResponse<Product>>> filterProducts({
    double? minPrice,
    double? maxPrice,
    int? categoryWooId,
    int limit,
    String? cursor,
  });
  Future<FeatureState<PaginatedResponse<Product>>> fetchProductsPage({
    int limit,
    String? cursor,
  });
  Future<FeatureState<List<Product>>> fetchAllProducts();
  Future<FeatureState<FeatureUnit>> upsertProductAdmin({
    required int wooId,
    required String name,
    required String price,
    required String description,
    required List<int> categoryWooIds,
    required List<String> imageUrls,
    required int stock,
    bool isNew,
  });
  int allocateAdminProductWooId();
  Future<FeatureState<FeatureUnit>> deleteProductByWooId(int wooId);
}

class BackendProductRepository implements ProductRepository {
  BackendProductRepository._();
  static final BackendProductRepository instance = BackendProductRepository._();

  static const Duration _homeBannersTtl = Duration(minutes: 3);
  FeatureState<List<WpHomeBannerSlide>>? _homeBannersCache;
  DateTime? _homeBannersFetchedAt;
  Future<FeatureState<List<WpHomeBannerSlide>>>? _homeBannersInFlight;

  int _pageFromCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return 0;
    final n = int.tryParse(cursor);
    return n != null && n >= 0 ? n : 0;
  }

  String? _nextPageCursor({required int page, required int pageSize, required int hitCount}) {
    if (hitCount < pageSize) return null;
    return '${page + 1}';
  }

  @override
  Future<FeatureState<List<ProductCategory>>> fetchAllCategories() async {
    final stores = await BackendOrdersClient.instance.fetchStores(limit: 100);
    if (stores == null) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.storeCategories);
    }
    final out = <ProductCategory>[];
    final seen = <String>{};
    for (final s in stores) {
      final sid = s['id']?.toString() ?? (throw StateError('NULL_RESPONSE'));
      if (sid.isEmpty) continue;
      final rows = await BackendOrdersClient.instance.fetchStoreCategories(sid);
      if (rows == null) {
        return FeatureState.criticalPublicDataFailure(FeatureIds.storeCategories);
      }
      for (final row in rows) {
        final key = row['id']?.toString() ??
            row['name']?.toString() ??
            (throw StateError('NULL_RESPONSE'));
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(_categoryFromBackendRow(row));
      }
    }
    return FeatureState.success(out);
  }

  @override
  Future<FeatureState<Product?>> fetchProductByWooId(int wooId) async {
    final stores = await BackendOrdersClient.instance.fetchStores(limit: 100);
    if (stores == null) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.products);
    }
    for (final s in stores) {
      final sid = s['id']?.toString() ?? (throw StateError('NULL_RESPONSE'));
      if (sid.isEmpty) continue;
      final rows = await BackendOrdersClient.instance.fetchProductsByStore(storeId: sid, limit: 200);
      if (rows == null) {
        return FeatureState.criticalPublicDataFailure(FeatureIds.products);
      }
      for (final row in rows) {
        final legacyId = (row['productCode']?.toString() ?? (throw StateError('NULL_RESPONSE'))).trim();
        if (legacyId == '$wooId') {
          return FeatureState.success(_productFromBackendRow(row));
        }
      }
    }
    return FeatureState.failure('DATA_NOT_FOUND');
  }

  @override
  Future<FeatureState<List<WpHomeBannerSlide>>> fetchHomeBanners({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _homeBannersCache != null &&
        _homeBannersFetchedAt != null &&
        now.difference(_homeBannersFetchedAt!) <= _homeBannersTtl) {
      return _homeBannersCache!;
    }
    if (!forceRefresh && _homeBannersInFlight != null) {
      return _homeBannersInFlight!;
    }
    Future<FeatureState<List<WpHomeBannerSlide>>> run() async => _fetchHomeBannersUncached();
    if (forceRefresh) {
      _homeBannersInFlight = null;
      final fresh = await run();
      _homeBannersCache = fresh;
      _homeBannersFetchedAt = DateTime.now();
      return fresh;
    }
    _homeBannersInFlight = run().then((r) {
      _homeBannersCache = r;
      _homeBannersFetchedAt = DateTime.now();
      _homeBannersInFlight = null;
      return r;
    });
    return _homeBannersInFlight!;
  }

  Future<FeatureState<List<WpHomeBannerSlide>>> _fetchHomeBannersUncached() async {
    try {
      final rows = await BackendOrdersClient.instance.fetchBanners();
      if (rows == null || rows.isEmpty) {
        return FeatureState.success(const <WpHomeBannerSlide>[
          WpHomeBannerSlide(
            imageUrl: _kBannerPlaceholderImage,
            title: 'عرض خاص',
            linkUrl: null,
          ),
        ]);
      }
      final slides = rows.map(_bannerFromBackendRow).toList();
      if (slides.isEmpty) {
        return FeatureState.success(const <WpHomeBannerSlide>[
          WpHomeBannerSlide(
            imageUrl: _kBannerPlaceholderImage,
            title: 'عرض خاص',
            linkUrl: null,
          ),
        ]);
      }
      return FeatureState.success(slides);
    } on Object {
      return FeatureState.success(const <WpHomeBannerSlide>[
        WpHomeBannerSlide(
          imageUrl: _kBannerPlaceholderImage,
          title: 'عرض خاص',
          linkUrl: null,
        ),
      ]);
    }
  }

  @override
  Future<FeatureState<PaginatedResponse<Product>>> searchProducts(
    String query, {
    int limit = 20,
    String? cursor,
  }) async {
    final page = _pageFromCursor(cursor);
    final hits = await BackendOrdersClient.instance.searchProducts(
      query: query,
      hitsPerPage: limit,
      page: page,
    );
    if (hits == null) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.productCatalogSearch);
    }
    final products = hits.map(_productFromSearchHit).toList();
    return FeatureState.success(
      PaginatedResponse<Product>(
        data: products,
        nextCursor: _nextPageCursor(page: page, pageSize: limit, hitCount: hits.length),
      ),
    );
  }

  @override
  Future<FeatureState<PaginatedResponse<Product>>> filterProducts({
    double? minPrice,
    double? maxPrice,
    int? categoryWooId,
    int limit = 20,
    String? cursor,
  }) async {
    final page = _pageFromCursor(cursor);
    final hits = await BackendOrdersClient.instance.searchProducts(
      query: '',
      hitsPerPage: limit,
      page: page,
      category: categoryWooId != null ? '$categoryWooId' : null,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
    if (hits == null) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.products);
    }
    final products = hits.map(_productFromSearchHit).toList();
    return FeatureState.success(
      PaginatedResponse<Product>(
        data: products,
        nextCursor: _nextPageCursor(page: page, pageSize: limit, hitCount: hits.length),
      ),
    );
  }

  @override
  Future<FeatureState<PaginatedResponse<Product>>> fetchProductsPage({
    int limit = 20,
    String? cursor,
  }) async {
    final page = _pageFromCursor(cursor);
    final hits = await BackendOrdersClient.instance.searchProducts(
      query: '',
      hitsPerPage: limit,
      page: page,
    );
    if (hits == null) {
      return FeatureState.criticalPublicDataFailure(FeatureIds.products);
    }
    final products = hits.map(_productFromSearchHit).toList();
    return FeatureState.success(
      PaginatedResponse<Product>(
        data: products,
        nextCursor: _nextPageCursor(page: page, pageSize: limit, hitCount: hits.length),
      ),
    );
  }

  @override
  Future<FeatureState<List<Product>>> fetchAllProducts() async {
    final pageState = await fetchProductsPage(limit: 200);
    return switch (pageState) {
      FeatureSuccess(:final data) => FeatureState.success(data.data),
      FeatureMissingBackend(:final featureName) => FeatureState.missingBackend(featureName),
      FeatureAdminNotWired(:final featureName) => FeatureState.adminNotWired(featureName),
      FeatureAdminMissingEndpoint(:final featureName) => FeatureState.failure('Unsupported state: $featureName'),
      FeatureCriticalPublicDataFailure(:final featureName, :final cause) =>
        FeatureState.criticalPublicDataFailure(featureName, cause),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
    };
  }

  @override
  Future<FeatureState<FeatureUnit>> upsertProductAdmin({
    required int wooId,
    required String name,
    required String price,
    required String description,
    required List<int> categoryWooIds,
    required List<String> imageUrls,
    required int stock,
    bool isNew = false,
  }) async {
    final parsedPrice = double.tryParse(price.trim()) ?? (throw StateError('INVALID_NUMERIC_DATA'));
    final payload = <String, dynamic>{
      'name': name.trim(),
      'price': parsedPrice,
      'description': description.trim(),
      'images': imageUrls,
      'stock': stock,
      if (categoryWooIds.isNotEmpty) 'categoryId': '${categoryWooIds.first}',
      'productCode': '$wooId',
    };
    final productId = isNew ? null : '$wooId';
    final res = await BackendOrdersClient.instance.upsertAdminProduct(productId: productId, payload: payload);
    if (res == null) {
      return FeatureState.failure('Failed to upsert product via backend.');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  @override
  int allocateAdminProductWooId() => ProductService.instance.allocateAdminProductWooId();

  @override
  Future<FeatureState<FeatureUnit>> deleteProductByWooId(int wooId) async {
    final directDelete = await BackendOrdersClient.instance.deleteAdminProductById('$wooId');
    if (directDelete) {
      return FeatureState.success(FeatureUnit.value);
    }

    final all = await BackendOrdersClient.instance.fetchPublicProducts(limit: 500);
    if (all == null) {
      return FeatureState.failure('Failed to resolve backend product id for wooId=$wooId');
    }
    String? backendId;
    for (final row in all) {
    final code = (row['productCode']?.toString() ?? (throw StateError('NULL_RESPONSE'))).trim();
      final id = (row['id']?.toString() ?? (throw StateError('NULL_RESPONSE'))).trim();
      if (code == '$wooId' && id.isNotEmpty) {
        backendId = id;
        break;
      }
    }
    if (backendId == null) {
      return FeatureState.failure('No backend product mapping found for wooId=$wooId');
    }
    final ok = await BackendOrdersClient.instance.deleteAdminProductById(backendId);
    if (!ok) {
      return FeatureState.failure('Failed to delete backend product id=$backendId');
    }
    return FeatureState.success(FeatureUnit.value);
  }
}
