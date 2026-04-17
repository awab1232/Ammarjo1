import '../../../core/utils/arabic_search_normalize.dart';
import 'models.dart';

/// فلاتر اختيارية لصفحة البحث (سعر + منطقة ضمن النص).
class StoreSearchFilters {
  const StoreSearchFilters({
    this.minPrice,
    this.maxPrice,
    this.region,
  });

  final double? minPrice;
  final double? maxPrice;
  /// اسم محافظة من [kJordanRegions] أو null لكل المناطق.
  final String? region;

  bool get hasActiveFilters =>
      minPrice != null || maxPrice != null || (region != null && region!.trim().isNotEmpty);

  StoreSearchFilters copyWith({
    double? minPrice,
    double? maxPrice,
    String? region,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    bool clearRegion = false,
  }) {
    return StoreSearchFilters(
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      region: clearRegion ? null : (region ?? this.region),
    );
  }
}

/// أول سعر رقمي للمنتج (للفلترة والواجهة).
double? storeProductPrimaryPrice(Product p) {
  final raw = p.price.trim();
  if (raw.isEmpty) return null;
  if (raw.contains('–') || raw.contains('-')) {
    final part = raw.split(RegExp(r'[–\-]')).first.trim();
    return double.tryParse(part);
  }
  return double.tryParse(raw);
}

/// كلمات مفتاحية إضافية للربط بين البحث والفئات (مثل: دهان → دهانات).
const List<List<String>> _keywordClusters = [
  ['دهان', 'دهانات', 'طلاء', 'معجون', 'بويه', 'بوية', 'جدار'],
  ['سباكه', 'سباكة', 'موسرجي', 'مواسير', 'خلاط'],
  ['كهرباء', 'كهربائي', 'سلك', 'لمبه', 'لمبة', 'فيش'],
  ['اسمنت', 'اسمنتيه', 'اسمنتية', 'طوب', 'رمل'],
  ['خشب', 'طوبار', 'نجاره', 'نجارة'],
  ['عده', 'عدة', 'ادوات', 'أدوات'],
];

Set<String> _expandedTokens(String normalizedQuery) {
  final out = <String>{normalizedQuery};
  if (normalizedQuery.isEmpty) return out;
  for (final cluster in _keywordClusters) {
    for (final word in cluster) {
      final nw = normalizeArabicForSearch(word);
      if (nw.isEmpty) continue;
      if (normalizedQuery.contains(nw) || nw.contains(normalizedQuery)) {
        out.addAll(cluster.map(normalizeArabicForSearch));
        break;
      }
    }
  }
  return out;
}

/// يتحقق إذا كان المنتج يطابق الاستعلام مع التطبيع العربي والفئات والوصف.
bool productMatchesStoreSearch(
  Product product,
  List<ProductCategory> categories,
  String rawQuery,
) {
  final q = normalizeArabicForSearch(rawQuery);
  if (q.isEmpty) return true;

  final tokens = _expandedTokens(q);
  bool anyTokenMatches(String hay) {
    final h = normalizeArabicForSearch(hay);
    if (h.isEmpty) return false;
    for (final t in tokens) {
      if (t.isNotEmpty && h.contains(t)) return true;
    }
    return false;
  }

  if (anyTokenMatches(product.name)) return true;

  final desc = stripHtmlForSearch(product.description);
  if (anyTokenMatches(desc)) return true;

  for (final cid in product.categoryIds) {
    for (final c in categories) {
      if (c.id == cid && anyTokenMatches(c.name)) return true;
    }
  }

  return false;
}

/// تطبيق فلاتر السعر والمنطقة (المنطقة تُطابق ضمن الاسم/الوصف المُطبَّع).
List<Product> applyStoreSearchFilters(
  List<Product> products,
  StoreSearchFilters filters,
) {
  if (!filters.hasActiveFilters) return products;

  return products.where((p) {
    final price = storeProductPrimaryPrice(p);
    if (filters.minPrice != null) {
      if (price == null || price < filters.minPrice!) return false;
    }
    if (filters.maxPrice != null) {
      if (price == null || price > filters.maxPrice!) return false;
    }
    final region = filters.region?.trim();
    if (region != null && region.isNotEmpty) {
      final nr = normalizeArabicForSearch(region);
      final blob = normalizeArabicForSearch(
        '${p.name} ${stripHtmlForSearch(p.description)}',
      );
      if (!blob.contains(nr)) return false;
    }
    return true;
  }).toList();
}

/// بحث كامل: نص + فلاتر.
List<Product> runStoreSearch({
  required List<Product> products,
  required List<ProductCategory> categories,
  required String query,
  required StoreSearchFilters filters,
}) {
  var list = products;
  final q = query.trim();
  if (q.isNotEmpty) {
    list = list.where((p) => productMatchesStoreSearch(p, categories, q)).toList();
  }
  list = applyStoreSearchFilters(list, filters);
  return list;
}
