import '../../features/store/domain/category_display_arabic.dart';
import '../../features/store/domain/models.dart';

/// قسم فرعي داخل قسم رئيسي — للشريط الأفقي وللثلاثة أقسام العمودية.
class MainSubCategoryDefinition {
  const MainSubCategoryDefinition({
    required this.titleAr,
    this.matchKeywords = const [],
  });

  final String titleAr;

  /// كلمات للمطابقة ضمن حقول المنتج والاسم (بدون إنجليزي في الواجهة).
  final List<String> matchKeywords;

  bool matchesProduct(Product p, String mainTitleAr) {
    final subCanon = CategoryDisplayArabic.canonical(p.subCategoryField);
    final catCanon = CategoryDisplayArabic.canonical(p.categoryField);
    if (subCanon == titleAr || catCanon == titleAr) return true;
    final hay = '${p.subCategoryField ?? ''} ${p.categoryField ?? ''} ${p.name}'
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    final t = titleAr.toLowerCase();
    if (hay.contains(t)) return true;
    for (final k in matchKeywords) {
      final kk = k.trim().toLowerCase();
      if (kk.isNotEmpty && hay.contains(kk)) return true;
    }
    return false;
  }
}

/// قسم رئيسي إلزامي على الرئيسية (١٢ قسماً).
class MainCategoryDefinition {
  const MainCategoryDefinition({
    required this.id,
    required this.titleAr,
    required this.subCategories,
    this.mainMatchKeywords = const [],
    this.isNewArrivals = false,
  });

  final String id;

  /// عنوان عربي فقط.
  final String titleAr;
  final List<MainSubCategoryDefinition> subCategories;

  /// كلمات إضافية لربط المنتج بالقسم الرئيسي.
  final List<String> mainMatchKeywords;

  /// وصل حديثاً — ترتيب زمني بدل التصنيفات النصية.
  final bool isNewArrivals;

  /// ثلاثة أقسام للعرض (أول ثلاثة عناصر من [subCategories]).
  List<MainSubCategoryDefinition> get sectionSubcategories {
    if (subCategories.length >= 3) return subCategories.take(3).toList();
    return List<MainSubCategoryDefinition>.from(subCategories);
  }

  /// كل العناصر للشريط الأفقي (عادة ≥ ٣).
  List<MainSubCategoryDefinition> get allSubCategories => subCategories;
}

/// الكتالوج الثابت — ١٢ قسماً رئيسياً بالعربية فقط.
abstract final class MainCategoryHierarchy {
  static const List<MainCategoryDefinition> ordered = <MainCategoryDefinition>[
    MainCategoryDefinition(
      id: 'sanitary',
      titleAr: 'الأدوات الصحية',
      mainMatchKeywords: ['صحي', 'حمام', 'خلاط', 'سيفون', 'أدوات صحية'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'خلاطات', matchKeywords: ['خلاط', 'خلاطات', 'mixer']),
        MainSubCategoryDefinition(titleAr: 'سيفونات', matchKeywords: ['سيفون', 'سيفونات', 'drain']),
        MainSubCategoryDefinition(titleAr: 'أطقم ومغاسل', matchKeywords: ['طقم', 'مغسلة', 'حوض']),
        MainSubCategoryDefinition(titleAr: 'إكسسوارات حمام', matchKeywords: ['إكسسوار', 'حامل', 'مناشف']),
      ],
    ),
    MainCategoryDefinition(
      id: 'electrical',
      titleAr: 'الأدوات الكهربائية',
      mainMatchKeywords: ['كهربائ', 'كهرباء', 'سخان', 'مفتاح'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'أفياش', matchKeywords: ['فيش', 'فيشة', 'أفياش', 'socket']),
        MainSubCategoryDefinition(titleAr: 'وصلات', matchKeywords: ['وصلة', 'وصلات', 'كابل']),
        MainSubCategoryDefinition(titleAr: 'إنارة', matchKeywords: ['إنارة', 'لمبة', 'LED', 'ضوء']),
        MainSubCategoryDefinition(titleAr: 'تمديدات', matchKeywords: ['تمديد', 'سخان ماء']),
      ],
    ),
    MainCategoryDefinition(
      id: 'hand_tools',
      titleAr: 'عدد يدوية',
      mainMatchKeywords: ['يدوية', 'مفك', 'كماشة', 'يدوي'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'مفاتيح', matchKeywords: ['مفك', 'مفاتيح', 'رنج']),
        MainSubCategoryDefinition(titleAr: 'كماشات', matchKeywords: ['كماشة', 'قص']),
        MainSubCategoryDefinition(titleAr: 'تجريف وقياس', matchKeywords: ['متر', 'مسطرة', 'منجل']),
        MainSubCategoryDefinition(titleAr: 'أدوات قطع', matchKeywords: ['منشار يدوي', 'سكين']),
      ],
    ),
    MainCategoryDefinition(
      id: 'power_tools',
      titleAr: 'عددٍ كهربائية',
      mainMatchKeywords: ['دريل', 'صاروخ', 'منشار كهرب', 'عدد كهرب'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'دريلات', matchKeywords: ['دريل', 'مثقاب']),
        MainSubCategoryDefinition(titleAr: 'صواريخ', matchKeywords: ['صاروخ', 'جلاخة']),
        MainSubCategoryDefinition(titleAr: 'مناشير كهربائية', matchKeywords: ['منشار']),
        MainSubCategoryDefinition(titleAr: 'ملحقات', matchKeywords: ['بت', 'قرص']),
      ],
    ),
    MainCategoryDefinition(
      id: 'paints',
      titleAr: 'الدهانات',
      mainMatchKeywords: ['دهان', 'طلاء', 'دلو', 'paint'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'دهانات داخلية', matchKeywords: ['داخلي', 'جدران']),
        MainSubCategoryDefinition(titleAr: 'دهانات خارجية', matchKeywords: ['خارجي', 'واجهات']),
        MainSubCategoryDefinition(titleAr: 'أدوات دهان', matchKeywords: ['فرشاة', 'رول', 'معجون']),
        MainSubCategoryDefinition(titleAr: 'مذيبات ودهانات خاصة', matchKeywords: ['مذيب', 'ورنيش']),
      ],
    ),
    MainCategoryDefinition(
      id: 'adhesives',
      titleAr: 'لواصق',
      mainMatchKeywords: ['لاصق', 'غراء', 'سيليكون', 'adhesive'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'سيليكون وبنفسج', matchKeywords: ['سيليكون']),
        MainSubCategoryDefinition(titleAr: 'غراء بناء', matchKeywords: ['غراء', 'لاصق']),
        MainSubCategoryDefinition(titleAr: 'لاصق بلاط', matchKeywords: ['بلاط']),
        MainSubCategoryDefinition(titleAr: 'شريط لاصق', matchKeywords: ['شريط']),
      ],
    ),
    MainCategoryDefinition(
      id: 'safety',
      titleAr: 'سلامة عامة',
      mainMatchKeywords: ['سلامة', 'خوذة', 'قفاز', 'نظارة', 'حماية'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'قفازات وملابس', matchKeywords: ['قفاز', 'بدلة']),
        MainSubCategoryDefinition(titleAr: 'خوذات ووجه', matchKeywords: ['خوذة', 'نظارة', 'وجه']),
        MainSubCategoryDefinition(titleAr: 'أحذية وأحزمة', matchKeywords: ['حذاء', 'حزام']),
        MainSubCategoryDefinition(titleAr: 'إنذار وإسعاف', matchKeywords: ['إسعاف', 'طوارئ']),
      ],
    ),
    MainCategoryDefinition(
      id: 'hoses',
      titleAr: 'برابيش',
      mainMatchKeywords: ['برابيش', 'خرطوم', 'مياه', 'ري'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'خراطيم مياه', matchKeywords: ['مياه', 'حديقة']),
        MainSubCategoryDefinition(titleAr: 'وصلات خرطوم', matchKeywords: ['وصلة', 'وصلات']),
        MainSubCategoryDefinition(titleAr: 'رشاشات', matchKeywords: ['رشاش', 'فوهة']),
        MainSubCategoryDefinition(titleAr: 'لفات وقطع', matchKeywords: ['لفافة']),
      ],
    ),
    MainCategoryDefinition(
      id: 'ladders',
      titleAr: 'سلالم',
      mainMatchKeywords: ['سلالم', 'سُلّم', 'ladder'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'سلالم ألمنيوم', matchKeywords: ['ألمنيوم']),
        MainSubCategoryDefinition(titleAr: 'سلالم فولاذ', matchKeywords: ['فولاذ', 'حديد']),
        MainSubCategoryDefinition(titleAr: 'سقالات صغيرة', matchKeywords: ['سقالة']),
        MainSubCategoryDefinition(titleAr: 'إكسسوارات سلالم', matchKeywords: ['مسند', 'حماية']),
      ],
    ),
    MainCategoryDefinition(
      id: 'pumps',
      titleAr: 'مضخات',
      mainMatchKeywords: ['مضخة', 'مضخات', 'غاطس', 'ضخ', 'pump'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'مضخات مياه', matchKeywords: ['مياه', 'منزلي']),
        MainSubCategoryDefinition(titleAr: 'غاطس وبئر', matchKeywords: ['غاطس', 'بئر']),
        MainSubCategoryDefinition(titleAr: 'مضخات ضغط', matchKeywords: ['ضغط', 'بوستر']),
        MainSubCategoryDefinition(titleAr: 'قطع وملحقات', matchKeywords: ['قطعة', 'طلمبة']),
      ],
    ),
    MainCategoryDefinition(
      id: 'building',
      titleAr: 'بناء',
      mainMatchKeywords: ['بناء', 'أسمنت', 'طوب', 'خرسانة', 'بلاط', 'construction'],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'أسمنت ومواد', matchKeywords: ['أسمنت', 'باطون']),
        MainSubCategoryDefinition(titleAr: 'بلاط وسيراميك', matchKeywords: ['بلاط', 'سيراميك']),
        MainSubCategoryDefinition(titleAr: 'حديد وتسليح', matchKeywords: ['حديد', 'تسليح']),
        MainSubCategoryDefinition(titleAr: 'إضافات بناء', matchKeywords: ['مادة', 'إصلاح']),
      ],
    ),
    MainCategoryDefinition(
      id: 'new_arrivals',
      titleAr: 'وصل حديثا',
      isNewArrivals: true,
      mainMatchKeywords: [],
      subCategories: <MainSubCategoryDefinition>[
        MainSubCategoryDefinition(titleAr: 'أحدث الوصول', matchKeywords: []),
        MainSubCategoryDefinition(titleAr: 'إضافات حديثة', matchKeywords: []),
        MainSubCategoryDefinition(titleAr: 'المزيد من الجديد', matchKeywords: []),
        MainSubCategoryDefinition(titleAr: 'كل الجديد', matchKeywords: []),
      ],
    ),
  ];

  static MainCategoryDefinition? byId(String id) {
    for (final m in ordered) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// منتجات تنتمي للقسم الرئيسي (قبل تصفية فرعية).
List<Product> productsForMainCategory(List<Product> all, MainCategoryDefinition main) {
  if (main.isNewArrivals) {
    final copy = List<Product>.from(all);
    copy.sort((a, b) {
      final da = a.createdAtFirestore;
      final db = b.createdAtFirestore;
      if (da != null && db != null) return db.compareTo(da);
      if (db != null) return 1;
      if (da != null) return -1;
      return b.id.compareTo(a.id);
    });
    return copy;
  }
  final mainAr = main.titleAr;
  final out = <Product>[];
  for (final p in all) {
    final c = CategoryDisplayArabic.canonical(p.categoryField);
    final s = CategoryDisplayArabic.canonical(p.subCategoryField);
    if (c == mainAr || s == mainAr) {
      out.add(p);
      continue;
    }
    final hay = '${p.categoryField ?? ''} ${p.subCategoryField ?? ''} ${p.name}'
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    var hit = false;
    for (final kw in main.mainMatchKeywords) {
      if (kw.trim().isEmpty) continue;
      if (hay.contains(kw.toLowerCase())) {
        hit = true;
        break;
      }
    }
    if (hit) out.add(p);
  }
  return out;
}

/// حتى ١٠ منتجات لقسم فرعي داخل قسم رئيسي.
List<Product> productsForSubSection(
  List<Product> all,
  MainCategoryDefinition main,
  MainSubCategoryDefinition sub,
  int sectionIndex,
) {
  if (main.isNewArrivals) {
    final sorted = productsForMainCategory(all, main);
    final start = sectionIndex * 10;
    if (start >= sorted.length) return <Product>[];
    final end = start + 10 > sorted.length ? sorted.length : start + 10;
    return sorted.sublist(start, end);
  }
  final pool = productsForMainCategory(all, main);
  final out = <Product>[];
  for (final p in pool) {
    if (sub.matchesProduct(p, main.titleAr)) out.add(p);
    if (out.length >= 10) break;
  }
  return out;
}

/// كل منتجات فرعي (لعرض المزيد).
List<Product> allProductsForSub(
  List<Product> all,
  MainCategoryDefinition main,
  MainSubCategoryDefinition sub,
  int sectionIndex,
) {
  if (main.isNewArrivals) {
    final sorted = productsForMainCategory(all, main);
    final start = sectionIndex * 10;
    if (start >= sorted.length) return <Product>[];
    return sorted.sublist(start);
  }
  final pool = productsForMainCategory(all, main);
  return pool.where((p) => sub.matchesProduct(p, main.titleAr)).toList();
}
