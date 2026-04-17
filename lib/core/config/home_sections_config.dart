/// إعدادات أقسام الصفحة الرئيسية (أفقي).
///
/// من لوحة ووردبريس: **منتجات → الأقسام** انسخ معرف القسم (ID) للأقسام المحددة.
/// إذا تُرك [null]، يُستخدم البحث النصي كبديل (أقل دقة).
abstract final class HomeSectionsConfig {
  /// قسم «دهانات جدران» — معرف WooCommerce
  static const int? wallPaintsCategoryId = null;

  /// قسم «لوازم السباكة»
  static const int? plumbingCategoryId = null;

  static const String wallPaintsSearchFallback = 'دهان';
  static const String plumbingSearchFallback = 'سباكة';
}
