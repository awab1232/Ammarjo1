/// مفاتيح حقل `page` لأقسام المنتجات (`product_categories`).
abstract final class AdminCategoryPages {
  static const String home = 'home';
  static const String stores = 'stores';
  static const String marketplace = 'marketplace';
  static const String technicians = 'technicians';

  static const List<String> orderedKeys = [home, stores, marketplace, technicians];

  static String labelAr(String key) {
    switch (key) {
      case home:
        return 'الصفحة الرئيسية';
      case stores:
        return 'المتاجر';
      case marketplace:
        return 'سوق المستعمل';
      case technicians:
        return 'الفنيون';
      default:
        return key;
    }
  }
}

/// مفاتيح حقل `page` لبانرات `home_banners`.
abstract final class AdminBannerPages {
  static const String home = 'home';
  static const String stores = 'stores';
  /// سوق المستعمل — يقبل أيضاً المفتاح القديم `marketplace` في Firestore.
  static const String usedMarket = 'used_market';
  static const String technicians = 'technicians';

  /// مفاتيح إضافية قد تظهر في بيانات قديمة.
  static const String legacyMarketplace = 'marketplace';
  static const String technicianRequest = 'technician_request';
  static const String myStore = 'my_store';

  static const List<String> orderedKeys = [home, stores, usedMarket, technicians];

  /// تطبيع للعرض والتجميع (دمج marketplace مع used_market).
  static String normalizePageKey(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty || t == home) return home;
    if (t == legacyMarketplace) return usedMarket;
    return t;
  }

  static String labelAr(String key) {
    final k = normalizePageKey(key);
    switch (k) {
      case home:
        return 'الرئيسية';
      case stores:
        return 'المتاجر';
      case usedMarket:
        return 'سوق المستعمل';
      case technicians:
        return 'الفنيون';
      case technicianRequest:
        return 'طلب فني';
      case myStore:
        return 'متجري';
      default:
        return key;
    }
  }
}
