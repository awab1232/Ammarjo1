import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, kDebugMode;

import '../../../../core/config/home_sections_config.dart';
import '../../../../core/config/shipping_policy.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/product_repository.dart';
import '../../../../core/network/network_errors.dart';
import '../../data/backend_catalog_client.dart';
import '../../../../core/data/repositories/store_settings_repository.dart';
import '../../domain/models.dart';
import '../../domain/home_banner_slide.dart';
import 'store_pagination.dart';

/// كتالوج المنتجات، الأقسام، البانر، وترقيم الصفحات.
class CatalogController extends ChangeNotifier {
  CatalogController();

  Timer? _shippingPolicyTimer;

  int _productOffset = 0;
  bool catalogHasMore = true;
  bool isLoadingMoreProducts = false;

  bool isLoading = false;
  String? errorMessage;

  List<Product> products = <Product>[];
  List<Product> homeBestSellers = <Product>[];
  List<Product> homeWallPaints = <Product>[];
  List<Product> homePlumbing = <Product>[];
  List<Product> homeNewArrivals = <Product>[];
  List<ProductCategory> categories = <ProductCategory>[];

  List<Product> bannerProducts = <Product>[];
  List<WpHomeBannerSlide> wpHomeBanners = <WpHomeBannerSlide>[];

  ShippingPolicy shippingPolicy = ShippingPolicy.defaults;

  static const int _bannerMax = 5;
  static const int _homeSectionPerPage = 12;

  List<ProductCategory> get categoriesForHomePage =>
      categories.where((c) => c.visibleOnPage('home')).toList();

  /// قائمة العرض للكتالوج العادي فقط (بدون بحث/تصفية).
  List<Product> get displayedProducts => products;

  List<Product> filterProductsBySearch(List<Product> list) => list;

  @override
  void dispose() {
    _shippingPolicyTimer?.cancel();
    super.dispose();
  }

  void _onCatalogStreamError(Object e, StackTrace st) {
    if (kDebugMode) {
      debugPrint('CatalogController stream error: $e');
      debugPrint('$st');
    }
    final net = networkUserMessage(e);
    errorMessage = net.isNotEmpty ? net : 'تعذر مزامنة الكتالوج. تحقق من الاتصال أو الصلاحيات.';
    isLoading = false;
    notifyListeners();
  }

  void attachFirestoreStreams() {
    _shippingPolicyTimer?.cancel();
    unawaited(_refreshShippingPolicy());
    _shippingPolicyTimer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(_refreshShippingPolicy()));
  }

  Future<void> _refreshShippingPolicy() async {
    try {
      final policy = await StoreSettingsRepository.fetchShippingPolicy();
      shippingPolicy = policy;
      notifyListeners();
    } on Object {
      _onCatalogStreamError(StateError('catalog_stream_error'), StackTrace.current);
    }
  }

  void _recomputeHomeSectionsFromProducts() {
    final list = products;
    List<Product> byName(String q) {
      final qq = q.trim().toLowerCase();
      if (qq.isEmpty) return list;
      return list.where((p) => p.name.toLowerCase().contains(qq)).toList();
    }

    homeBestSellers = list.take(_homeSectionPerPage).toList();
    homeWallPaints = HomeSectionsConfig.wallPaintsCategoryId != null
        ? list
            .where((p) => p.categoryIds.contains(HomeSectionsConfig.wallPaintsCategoryId!))
            .take(_homeSectionPerPage)
            .toList()
        : byName(HomeSectionsConfig.wallPaintsSearchFallback).take(_homeSectionPerPage).toList();
    homePlumbing = HomeSectionsConfig.plumbingCategoryId != null
        ? list
            .where((p) => p.categoryIds.contains(HomeSectionsConfig.plumbingCategoryId!))
            .take(_homeSectionPerPage)
            .toList()
        : byName(HomeSectionsConfig.plumbingSearchFallback).take(_homeSectionPerPage).toList();
    homeNewArrivals = list.take(_homeSectionPerPage).toList();
  }

  Future<void> reloadCatalogAfterMigration() async {
    notifyListeners();
  }

  Future<FeatureState<List<Product>>> fetchProductsByCategory(int categoryId, {int perPage = 100}) async {
    return FeatureState.success(
      products.where((p) => p.categoryIds.contains(categoryId)).take(perPage).toList(),
    );
  }

  Future<FeatureState<List<Product>>> fetchProductsByTag(int tagId, {int perPage = 100}) async {
    return FeatureState.success(
      products.where((p) => p.tagIds.contains(tagId)).take(perPage).toList(),
    );
  }

  Future<FeatureState<List<ProductCategory>>> fetchChildCategories(int parentId) async {
    return FeatureState.success(
      categories.where((c) => c.parent == parentId && c.visibleOnPage('home')).toList(),
    );
  }

  Future<void> loadInitialProductsPage() async {
    isLoading = true;
    errorMessage = null;
    _productOffset = 0;
    catalogHasMore = true;
    products.clear();
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final rowsState = await BackendCatalogClient.instance.fetchProducts(limit: kStoreCatalogPageSize);
      if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
        errorMessage = 'حدث خطأ أثناء تحميل المنتجات من Firestore.';
        return;
      }
      final rows = rowsState.data;
      products = rows
          .map((r) => Product(
                id: (r['id']?.toString() ?? '').hashCode.abs(),
                name: r['name']?.toString() ?? '',
                description: r['description']?.toString() ?? '',
                price: r['price']?.toString() ?? '0',
                images: <String>[
                  if (((r['imageUrl'] ?? r['image'])?.toString().trim() ?? '').isNotEmpty)
                    (r['imageUrl'] ?? r['image']).toString(),
                ],
                categoryIds: const <int>[],
              ))
          .toList();
      _productOffset = products.length;
      catalogHasMore = false;
      _recomputeHomeSectionsFromProducts();
      await loadBannerProducts();
    } on Object {
      errorMessage = 'حدث خطأ أثناء تحميل المنتجات من Firestore.';
    } finally {
      sw.stop();
      debugPrint('⏱️ Catalog loadInitialProductsPage took: ${sw.elapsedMilliseconds}ms (count=${products.length})');
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextProductsPage() async {
    if (!catalogHasMore || isLoadingMoreProducts) return;
    isLoadingMoreProducts = true;
    notifyListeners();
    final sw = Stopwatch()..start();
    try {
      final rowsState = await BackendCatalogClient.instance.fetchProducts(limit: kStoreCatalogPageSize);
      if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
        errorMessage = 'تعذر تحميل المزيد من المنتجات.';
        return;
      }
      final rows = rowsState.data;
      final pageProducts = rows
          .skip(_productOffset)
          .map((r) => Product(
                id: (r['id']?.toString() ?? '').hashCode.abs(),
                name: r['name']?.toString() ?? '',
                description: r['description']?.toString() ?? '',
                price: r['price']?.toString() ?? '0',
                images: <String>[
                  if (((r['imageUrl'] ?? r['image'])?.toString().trim() ?? '').isNotEmpty)
                    (r['imageUrl'] ?? r['image']).toString(),
                ],
                categoryIds: const <int>[],
              ))
          .toList();
      products = [...products, ...pageProducts];
      _productOffset = products.length;
      catalogHasMore = false;
      _recomputeHomeSectionsFromProducts();
    } on Object {
      errorMessage = 'تعذر تحميل المزيد من المنتجات.';
    } finally {
      sw.stop();
      debugPrint('⏱️ Catalog loadNextProductsPage took: ${sw.elapsedMilliseconds}ms (+${products.length})');
      isLoadingMoreProducts = false;
      notifyListeners();
    }
  }

  /// واجهة صريحة مطلوبة لتهيئة الصفحة الرئيسية (pagination أولية = 20).
  Future<void> loadInitialProducts() => loadInitialProductsPage();

  /// واجهة صريحة مطلوبة للتحميل عند التمرير.
  Future<void> loadMoreProducts() => loadNextProductsPage();

  Future<void> loadProducts() async {
    await loadInitialProductsPage();
  }

  Future<void> loadCategories() async {
    try {
      final rowsState = await BackendCatalogClient.instance.fetchCategories();
      if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
        if (errorMessage == null || errorMessage!.isEmpty) {
          errorMessage = 'تعذر تحميل الأقسام.';
        }
        return;
      }
      final rows = rowsState.data;
      categories = rows
          .map((r) => ProductCategory(
                id: (r['id']?.toString() ?? '').hashCode.abs(),
                name: r['name']?.toString() ?? '',
                parent: 0,
                imageUrl: r['imageUrl']?.toString() ?? '',
              ))
          .toList();
    } on Object {
      if (errorMessage == null || errorMessage!.isEmpty) {
        errorMessage = 'تعذر تحميل الأقسام.';
      }
    }
    notifyListeners();
  }

  Future<void> loadWpHomeBanners() async {
    try {
      final state = await BackendProductRepository.instance.fetchHomeBanners();
      switch (state) {
        case FeatureSuccess(:final data):
          wpHomeBanners = data;
        default:
          wpHomeBanners = const <WpHomeBannerSlide>[];
      }
    } on Object {
      wpHomeBanners = const <WpHomeBannerSlide>[];
    }
    notifyListeners();
  }

  Future<void> loadBannerProducts() async {
    try {
      var list = products.where((p) => p.images.isNotEmpty).take(_bannerMax).toList();
      if (list.isEmpty) {
        list = products.take(_bannerMax).toList();
      }
      bannerProducts = list;
    } on Object {
      bannerProducts = products.where((p) => p.images.isNotEmpty).take(_bannerMax).toList();
    }
    notifyListeners();
  }

  Future<void> loadHomeSections() async {
    _recomputeHomeSectionsFromProducts();
    notifyListeners();
  }
}
