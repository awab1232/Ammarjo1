import 'package:ammar_store/features/store/domain/models.dart';

/// نوع تصفية قسم الصفحة الرئيسية.
enum HomeSectionFilterKind {
  /// أحدث المنتجات حسب [Product.createdAtFirestore] ثم [Product.id].
  newArrivals,

  /// عروض — كلمات مفتاحية (عروض، خصم، …).
  offers,

  /// مطابقة كلمات ضمن حقول `category` / `subCategory` (والاسم عند غياب التصنيف).
  categoryKeywords,
}

/// تعريف قسم أفقي واحد (عناوين عربية فقط — الترتيب في [HomeCategorySections.ordered]).
class HomeCategorySectionDefinition {
  const HomeCategorySectionDefinition({
    required this.title,
    required this.kind,
    this.keywords = const [],
  });

  final String title;
  final HomeSectionFilterKind kind;
  final List<String> keywords;
}

/// الأقسام بالترتيب المطلوب — التصفية من حقول Firestore `category` و `subCategory`.
abstract final class HomeCategorySections {
  static const List<HomeCategorySectionDefinition> ordered = <HomeCategorySectionDefinition>[
    HomeCategorySectionDefinition(
      title: 'وصل حديثاً',
      kind: HomeSectionFilterKind.newArrivals,
    ),
    HomeCategorySectionDefinition(
      title: 'العروض',
      kind: HomeSectionFilterKind.offers,
      keywords: <String>[
        'عروض',
        'عرض',
        'offer',
        'offers',
        'sale',
        'تخفيض',
        'خصم',
        'discount',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'الأدوات الصحية',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'صحي',
        'sanitary',
        'أدوات صحية',
        'الأدوات الصحية',
        'حمام',
        'خلاط',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'الأدوات الكهربائية',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'كهربائ',
        'electrical',
        'electric',
        'الأدوات الكهربائية',
        'سخان',
        'مفاتيح',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'عدد يدوية',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'يدوية',
        'hand tool',
        'hand tools',
        'عدد يدوية',
        'مفك',
        'كماشة',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'عددٍ كهربائية',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'power tool',
        'power tools',
        'عدد كهربائية',
        'دريل',
        'صاروخ',
        'منشار كهرب',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'الدهانات',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'دهان',
        'paints',
        'paint',
        'الدهانات',
        'طلاء',
        'دلو',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'لواصق',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'لاصق',
        'adhesive',
        'adhesives',
        'glue',
        'لواصق',
        'سيليكون',
        'غراء',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'سلامة عامة',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'سلامة',
        'سلامة عامة',
        'safety',
        'خوذة',
        'قفاز',
        'نظارة',
        'حماية',
        'مستلزمات السلامة',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'برابيش',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'برابيش',
        'برابيش المياه',
        'خرطوم',
        'hose',
        'hoses',
        'مياه',
        'ري',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'سلالم',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'سلالم',
        'السلالم',
        'ladder',
        'ladders',
        'سُلّم',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'بناء',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'بناء',
        'construction',
        'بلاط',
        'أسمنت',
        'طوب',
        'خرسانة',
        'لوازم البناء',
      ],
    ),
    HomeCategorySectionDefinition(
      title: 'مضخات',
      kind: HomeSectionFilterKind.categoryKeywords,
      keywords: <String>[
        'مضخة',
        'مضخات',
        'pump',
        'pumps',
        'غاطس',
        'ضخ',
      ],
    ),
  ];

  static List<Product> productsForSection(List<Product> all, HomeCategorySectionDefinition def) {
    switch (def.kind) {
      case HomeSectionFilterKind.newArrivals:
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
      case HomeSectionFilterKind.offers:
        return all.where((p) => _matchesKeywords(p, def.keywords, includeProductName: true)).toList();
      case HomeSectionFilterKind.categoryKeywords:
        return all.where((p) => _matchesKeywords(p, def.keywords, includeProductName: false)).toList();
    }
  }

  static bool _matchesKeywords(Product p, List<String> keywords, {required bool includeProductName}) {
    if (keywords.isEmpty) return false;
    final cat = '${p.categoryField ?? ''} ${p.subCategoryField ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    final hasCat = (p.categoryField?.trim().isNotEmpty ?? false) ||
        (p.subCategoryField?.trim().isNotEmpty ?? false);
    final String hay;
    if (includeProductName) {
      hay = '$cat ${p.name.toLowerCase()}';
    } else if (hasCat) {
      hay = cat;
    } else {
      hay = p.name.toLowerCase();
    }
    for (final k in keywords) {
      final kk = k.trim().toLowerCase();
      if (kk.isEmpty) continue;
      if (hay.contains(kk)) return true;
    }
    return false;
  }
}
