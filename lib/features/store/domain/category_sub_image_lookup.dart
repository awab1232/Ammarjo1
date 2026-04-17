import '../../../core/config/main_category_hierarchy.dart';
import 'models.dart';

/// يطابق أسماء أقسام Firestore (`product_categories`) مع التصنيفات الثابتة في [MainCategoryHierarchy]
/// لاسترجاع [ProductCategory.imageUrl] للعرض في شريط الأقسام الفرعية.
String? resolveSubCategoryImageUrl({
  required List<ProductCategory> categories,
  required MainCategoryDefinition main,
  required MainSubCategoryDefinition sub,
}) {
  if (categories.isEmpty) return '';

  String norm(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.startsWith('ال') && t.length > 2) t = t.substring(2);
    return t.toLowerCase();
  }

  bool nameMatch(String a, String b) {
    final na = norm(a);
    final nb = norm(b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.contains(nb) || nb.contains(na)) return true;
    return false;
  }

  ProductCategory? mainRoot;
  for (final c in categories) {
    if (c.parent == 0 && nameMatch(c.name, main.titleAr)) {
      mainRoot = c;
      break;
    }
  }
  if (mainRoot == null) {
    for (final c in categories) {
      if (nameMatch(c.name, main.titleAr)) {
        mainRoot = c;
        break;
      }
    }
  }

  final root = mainRoot;
  if (root != null) {
    for (final c in categories) {
      if (c.parent == root.id && nameMatch(c.name, sub.titleAr)) {
        final u = c.imageUrl.trim();
        if (u.isNotEmpty) return u;
      }
    }
  }

  for (final c in categories) {
    if (nameMatch(c.name, sub.titleAr)) {
      final u = c.imageUrl.trim();
      if (u.isNotEmpty) return u;
    }
  }

  return '';
}
