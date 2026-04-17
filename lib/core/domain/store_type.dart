/// يطابق قيم `users.store_type` / `/auth/me` من الخادم.
enum StoreType {
  /// مواد بناء / مسار `construction_store`
  construction,
  /// أدوات منزلية / `home_store`
  home,
  /// مسار جملة مرتبط بالمتجر
  wholesale,
  /// غير محدد أو قيمة غير معروفة
  unknown,
}

/// تحويل نص الخادم: `construction_store | home_store | wholesale_store`
StoreType storeTypeFromBackendString(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return StoreType.unknown;
  if (s == 'construction_store' || s == 'construction') {
    return StoreType.construction;
  }
  if (s == 'home_store' || s == 'home' || s == 'home_tools') {
    return StoreType.home;
  }
  if (s == 'wholesale_store' || s == 'wholesale') {
    return StoreType.wholesale;
  }
  return StoreType.unknown;
}
