export '../../features/stores/data/store_categories_repository.dart'
    show StoreCategoryEntry, fetchStoreCategoriesFromFirestore, watchActiveStoreCategories, kStoresCategoryFallbackImageUrls;

/// محافظات ومناطق الأردن للتصفية ونماذج الطلبات.
const List<String> kJordanCities = [
  'عمان',
  'الزرقاء',
  'إربد',
  'العقبة',
  'المفرق',
  'جرش',
  'عجلون',
  'السلط',
  'مادبا',
  'الكرك',
  'الطفيلة',
  'معان',
  'الأردن كاملة',
];

/// تصنيفات متعلقة بمواد البناء والمتجر (عروض، متاجر، فلترة).
/// للتصنيفات الديناميكية من الخادم انظر [fetchStoreCategoriesFromFirestore] و [watchActiveStoreCategories].
const List<String> kBuildingCategories = [
  'مواد البناء الأساسية',
  'أدوات كهربائية',
  'دهانات وديكور',
  'سباكة',
  'نجارة وأبواب',
  'بلاط وأرضيات',
  'عزل ومواد خاصة',
  'أدوات ومعدات',
];
