import '../../../core/utils/web_image_url.dart';
import 'category_display_arabic.dart';
import 'models.dart';

/// قسم للعرض على الرئيسية — مُستخرج من حقول المنتجات فقط (بدون مجموعة `product_categories`).
class ProductDerivedCategory {
  const ProductDerivedCategory({
    required this.label,
    this.imageUrl,
  });

  /// اسم عربي موحّد ([CategoryDisplayArabic.canonical]).
  final String label;
  final String? imageUrl;
}

bool _productMatchesDisplayLabel(Product p, String displayAr) {
  final c = CategoryDisplayArabic.canonical(p.categoryField);
  final s = CategoryDisplayArabic.canonical(p.subCategoryField);
  return c == displayAr || s == displayAr;
}

/// يجمع التصنيفات الفريدة من المنتجات، يعرّفها عربياً، ويرتّبها.
List<ProductDerivedCategory> deriveCategoriesFromProducts(List<Product> products) {
  final seen = <String>{};
  final order = <String>[];
  for (final p in products) {
    for (final raw in <String?>[p.categoryField, p.subCategoryField]) {
      final ar = CategoryDisplayArabic.canonical(raw);
      if (ar.isEmpty) continue;
      if (seen.add(ar)) order.add(ar);
    }
  }
  order.sort((a, b) => a.compareTo(b));
  return order.map((label) {
    String? img;
    for (final p in products) {
      if (_productMatchesDisplayLabel(p, label)) {
        img = getFirstImage(p.images);
        if (img != null && img.isNotEmpty) break;
      }
    }
    return ProductDerivedCategory(label: label, imageUrl: img);
  }).toList();
}

/// منتجات تطابق التسمية العربية المعروضة في الشريط.
List<Product> productsMatchingCategoryLabel(List<Product> products, String displayLabel) {
  final t = displayLabel.trim();
  if (t.isEmpty) return <Product>[];
  return products.where((p) => _productMatchesDisplayLabel(p, t)).toList();
}
