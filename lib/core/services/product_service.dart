import '../../features/store/domain/models.dart';
import '../../features/store/domain/wp_home_banner.dart';

/// Portable catalog rules: product/category/banner mapping and admin payloads.
/// No Firebase — callers pass raw `Map` data (and optional [DateTime] from Timestamp conversion).
class ProductService {
  ProductService._();
  static final ProductService instance = ProductService._();

  String? trimmedString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  String? firstNonEmptyString(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final s = trimmedString(d[k]);
      if (s != null) return s;
    }
    return null;
  }

  /// يفضّل `nameAr` من البيانات لعرض العربية فقط.
  String categoryDisplayName(Map<String, dynamic> d) {
    final ar = d['nameAr']?.toString().trim();
    if (ar != null && ar.isNotEmpty) return ar;
    return d['name']?.toString().trim() ?? '';
  }

  String categoryImageUrlFromMap(Map<String, dynamic> d) {
    var catImg = trimmedString(d['imageUrl']) ?? trimmedString(d['image_url']) ?? '';
    if (catImg.isEmpty) {
      final im = d['image'];
      if (im is Map<String, dynamic>) {
        catImg = trimmedString(im['src']) ?? trimmedString(im['url']) ?? '';
      } else if (im is String) {
        catImg = im.trim();
      }
    }
    if (catImg.isEmpty) {
      catImg = trimmedString(d['thumbnailUrl']) ?? trimmedString(d['photoUrl']) ?? '';
    }
    return catImg;
  }

  String categoryPageFromMap(Map<String, dynamic> d) {
    final p = trimmedString(d['page']) ?? 'home';
    return p.isEmpty ? 'home' : p;
  }

  ProductCategory? categoryFromFirestoreData(String docId, Map<String, dynamic> d) {
    final id = (d['wooId'] as num?)?.toInt() ?? int.tryParse(docId.replaceFirst('woo_', '')) ?? 0;
    if (id == 0) return null;
    return ProductCategory(
      id: id,
      name: categoryDisplayName(d),
      imageUrl: categoryImageUrlFromMap(d),
      parent: (d['parent'] as num?)?.toInt() ?? 0,
      categoryPage: categoryPageFromMap(d),
    );
  }

  bool bannerIsActive(Map<String, dynamic> d) {
    final a = d['active'];
    if (a is bool) return a;
    final i = d['isActive'];
    if (i is bool) return i;
    return true;
  }

  bool bannerIsForHomePage(Map<String, dynamic> d) {
    if (!bannerIsActive(d)) return false;
    final p = trimmedString(d['page']) ?? '';
    return p.isEmpty || p == 'home';
  }

  bool bannerIsForPage(Map<String, dynamic> d, String page) {
    if (!bannerIsActive(d)) return false;
    final p = trimmedString(d['page']) ?? '';
    if (page == 'home') return p.isEmpty || p == 'home';
    if (page == 'used_market') {
      return p == 'used_market' || p == 'marketplace';
    }
    return p == page;
  }

  /// شريحة بانر للصفحة الرئيسية (بعد ترتيب المستندات).
  WpHomeBannerSlide? homeBannerSlideForHome(Map<String, dynamic> d) {
    if (!bannerIsForHomePage(d)) return null;
    final url = d['imageUrl'] as String? ?? '';
    if (url.isEmpty) return null;
    return WpHomeBannerSlide(
      imageUrl: url,
      linkUrl: d['linkUrl'] as String?,
      title: d['title'] as String?,
    );
  }

  WpHomeBannerSlide? homeBannerSlideForPage(Map<String, dynamic> d, String page) {
    if (!bannerIsForPage(d, page)) return null;
    final url = d['imageUrl'] as String? ?? '';
    if (url.isEmpty) return null;
    return WpHomeBannerSlide(
      imageUrl: url,
      linkUrl: d['linkUrl'] as String?,
      title: d['title'] as String?,
    );
  }

  int compareBannerSortOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sa = (a['sortOrder'] as num?)?.toInt() ?? 0;
    final sb = (b['sortOrder'] as num?)?.toInt() ?? 0;
    return sa.compareTo(sb);
  }

  /// استخراج روابط صور البانر من وثائق `marketplace_banners` (للسوق / العروض).
  List<String> marketplaceBannerImageUrls(
    Iterable<Map<String, dynamic>> docs, {
    int maxCount = 3,
  }) {
    final urls = <String>[];
    for (final m in docs) {
      final active = m['active'] ?? m['isActive'];
      if (active is bool && !active) continue;
      final u = m['imageUrl']?.toString().trim() ?? '';
      if (u.isNotEmpty) {
        urls.add(u);
      }
      if (urls.length >= maxCount) break;
    }
    return urls;
  }

  /// بحث: تطبيع الاستعلام ونهاية نطاق بادئة الاسم.
  String searchQueryLowerTrimmed(String query) => query.trim().toLowerCase();

  bool searchIsSingleToken(String raw) => !RegExp(r'\s').hasMatch(raw);

  String searchNamePrefixUpperBound(String raw) => '$raw\uf8ff';

  /// منطق اختيار مسار `searchTerms` (كلمة واحدة، طول ≥ 2).
  bool shouldPreferSearchTermsPath(String rawQuery) {
    final raw = rawQuery.trim();
    if (raw.isEmpty) return false;
    final qLower = searchQueryLowerTrimmed(raw);
    return searchIsSingleToken(raw) && qLower.length >= 2;
  }

  Product? productFromFirestoreData(
    Map<String, dynamic> d, {
    required String documentId,
    DateTime? createdAtFirestore,
  }) {
    final id = (d['wooId'] as num?)?.toInt() ?? 0;
    if (id == 0) return null;
    final rawList = d['imageUrls'] ?? d['image_urls'] ?? d['images'];
    final imageUrls = <String>[];
    if (rawList is List<dynamic>) {
      for (final e in rawList) {
        final s = e.toString().trim();
        if (s.isNotEmpty) imageUrls.add(s);
      }
    } else if (rawList is String && rawList.trim().isNotEmpty) {
      imageUrls.add(rawList.trim());
    }
    void addImageUrl(String? u) {
      final s = trimmedString(u);
      if (s == null) return;
      if (!imageUrls.contains(s)) imageUrls.add(s);
    }

    final singleUrl = trimmedString(d['imageUrl']);
    if (imageUrls.isEmpty && singleUrl != null) {
      imageUrls.add(singleUrl);
    }
    for (final key in const ['images', 'photos', 'imageList', 'gallery']) {
      final list = d[key];
      if (list is List<dynamic>) {
        for (final e in list) {
          if (e is String) {
            addImageUrl(e);
          } else if (e is Map) {
            addImageUrl((e['url'] ?? e['src'] ?? e['imageUrl'])?.toString());
          }
        }
      }
    }
    final imgObj = d['image'];
    if (imgObj is Map<String, dynamic>) {
      addImageUrl((imgObj['src'] ?? imgObj['url'] ?? imgObj['imageUrl'])?.toString());
    }
    addImageUrl(d['thumbnailUrl']?.toString());
    addImageUrl(d['photoUrl']?.toString());
    final cats = (d['categoryWooIds'] as List<dynamic>?) ?? List<dynamic>.empty(growable: false);
    final categoryIds = cats.map((e) => (e as num).toInt()).toList();
    final tags = (d['tagWooIds'] as List<dynamic>?) ?? List<dynamic>.empty(growable: false);
    final tagIds = tags.map((e) => (e as num).toInt()).toList();
    final categoryField = firstNonEmptyString(d, const [
      'category',
      'categoryName',
      'categoryLabel',
      'mainCategory',
      'productCategory',
      'Category',
      'product_category',
    ]);
    final subCategoryField = firstNonEmptyString(d, const [
      'subCategory',
      'subCategoryName',
      'subCategoryLabel',
      'sub_category',
    ]);
    final stockRaw = d['stock'] ?? d['stock_quantity'];
    final stockVal = stockRaw is num
        ? stockRaw.toInt()
        : int.tryParse(stockRaw?.toString() ?? '') ?? -1;
    var stockStatus = (d['stockStatus'] ?? d['stock_status'] ?? 'instock').toString().trim().toLowerCase();
    if (!const {'instock', 'outofstock', 'onbackorder'}.contains(stockStatus)) {
      stockStatus = 'instock';
    }
    return Product(
      id: id,
      name: d['name'] as String? ?? '',
      description: d['description'] as String? ?? '',
      price: d['price'] == null ? '' : d['price'].toString(),
      images: imageUrls,
      categoryIds: categoryIds,
      tagIds: tagIds,
      categoryField: categoryField,
      subCategoryField: subCategoryField,
      createdAtFirestore: createdAtFirestore,
      stock: stockVal,
      stockStatus: stockStatus,
    );
  }

  /// حقول مستند المنتج في لوحة الإدارة — **بدون** طوابع خادم (يضيفها مصدر البيانات).
  Map<String, dynamic> buildAdminProductUpsertFields({
    required int wooId,
    required String name,
    required String price,
    required String description,
    required List<int> categoryWooIds,
    required List<String> imageUrls,
    required int stock,
  }) {
    return <String, dynamic>{
      'wooId': wooId,
      'name': name,
      'price': price,
      'description': description,
      'categoryWooIds': categoryWooIds,
      'imageUrls': imageUrls,
      'stock': stock,
      'stockStatus': stock <= 0 ? 'outofstock' : 'instock',
    };
  }

  /// معرّف تصنيف جديد (أكبر معرّف حالي + 1).
  int nextCategoryWooIdFromCategories(List<ProductCategory> categories) {
    var m = 0;
    for (final c in categories) {
      if (c.id > m) m = c.id;
    }
    return m + 1;
  }

  /// معرّف `wooId` لمنتج جديد من لوحة الإدارة.
  int allocateAdminProductWooId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return 1_000_000 + (ms % 1_000_000_000);
  }
}
