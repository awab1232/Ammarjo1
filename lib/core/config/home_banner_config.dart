/// بانر الصفحة الرئيسية — **احتياطي** عندما لا تُحمّل بانرات ووردبريس (`home_banners_wp_config`):
/// الصور من **منتجات مميزة** (Featured) في WooCommerce.
///
/// إن لم يوجد منتج مميز بصورة، يُستخدم [fallbackCategoryId] إن وُجد، ثم أي منتجات لها صور.
abstract final class HomeBannerConfig {
  /// معرف قسم اختياري: يُحمّل منه أحدث المنتجات بصور إذا فشلت المميزة.
  static const int? fallbackCategoryId = null;
}
