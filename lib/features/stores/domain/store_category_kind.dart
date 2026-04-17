/// قيم حقل `category` في `stores` و`store_requests` للتمييز بين أنواع المتاجر.
abstract final class StoreCategoryKind {
  StoreCategoryKind._();

  /// متاجر الأدوات المنزلية (نفس منطق متاجر مواد البناء مع مصدر بيانات منفصل).
  static const String homeTools = 'HOME_TOOLS';
}
