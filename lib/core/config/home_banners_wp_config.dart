/// بانرات الصفحة الرئيسية من **ووردبريس** (REST API، بدون مفاتيح Woo).
///
/// أنشئ في لوحة ووردبريس **تصنيفاً** (مثلاً slug: `home-banners`) وأضف **مقالات** واضبط لكل مقال **صورة بارزة**.
/// تُعرض الصور في السلايدر العلوي بالترتيب حسب [orderBy] / [order].
///
/// اترك [categorySlug] فارغاً **و** [categoryId] = null لتعطيل الجلب من ووردبريس والاعتماد على بانر المنتجات فقط.
abstract final class HomeBannersWpConfig {
  /// مثال: `home-banners` — من **مقالات → التصنيفات** انسخ الـ slug.
  static const String categorySlug = 'home-banners';

  /// إن وُجد، يُستخدم مباشرة دون طلب تصنيف بالـ slug.
  static const int? categoryId = null;

  static const int perPage = 10;

  static const String orderBy = 'date';
  static const String order = 'desc';
}
