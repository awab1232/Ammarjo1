/// تحويل قيمة التصنيف من المنتج (إنجليزي/عربي/مرادفات) إلى اسم عربي موحّد لعرض الشريط الرئيسي.
abstract final class CategoryDisplayArabic {
  CategoryDisplayArabic._();

  /// مرادفات عربية → شكل موحّد واحد للعرض والدمج.
  static const Map<String, String> _arabicCanonical = {
    'دهانات': 'الدهانات',
    'الدهانات': 'الدهانات',
    'دهان': 'الدهانات',
    'طلاء': 'الدهانات',
    'أدوات صحية': 'الأدوات الصحية',
    'الأدوات الصحية': 'الأدوات الصحية',
    'الأدوات الكهربائية': 'الأدوات الكهربائية',
    'صحي': 'الأدوات الصحية',
    'عدد يدوية': 'عدد يدوية',
    'يدوية': 'عدد يدوية',
    'عددٍ كهربائية': 'عددٍ كهربائية',
    'عدد كهربائية': 'عددٍ كهربائية',
    'لواصق': 'لواصق',
    'لواصق بأنواعها': 'لواصق',
    'سلامة عامة': 'سلامة عامة',
    'مستلزمات السلامة العامة': 'سلامة عامة',
    'مستلزمات السلامة': 'سلامة عامة',
    'برابيش': 'برابيش',
    'برابيش المياه': 'برابيش',
    'سلالم': 'سلالم',
    'السلالم': 'سلالم',
    'بناء': 'بناء',
    'لوازم البناء': 'بناء',
    'مضخات': 'مضخات',
    'المضخات بأنواعها': 'مضخات',
    'العروض': 'العروض',
    'عروض': 'العروض',
  };

  /// إنجليزي (بعد trim + lowercase) → عربي للعرض.
  static const Map<String, String> _englishToArabic = {
    'sanitary ware': 'الأدوات الصحية',
    'sanitary': 'الأدوات الصحية',
    'plumbing': 'الأدوات الصحية',
    'bathroom': 'الأدوات الصحية',
    'paints': 'الدهانات',
    'paint': 'الدهانات',
    'painting': 'الدهانات',
    'electrical': 'الأدوات الكهربائية',
    'electronics': 'الأدوات الكهربائية',
    'electrical tools': 'الأدوات الكهربائية',
    'electric': 'الأدوات الكهربائية',
    'hand tools': 'عدد يدوية',
    'hand tool': 'عدد يدوية',
    'power tools': 'عددٍ كهربائية',
    'power tool': 'عددٍ كهربائية',
    'adhesives': 'لواصق',
    'adhesive': 'لواصق',
    'glue': 'لواصق',
    'silicone': 'لواصق',
    'safety': 'سلامة عامة',
    'safety equipment': 'سلامة عامة',
    'hoses': 'برابيش',
    'hose': 'برابيش',
    'water hose': 'برابيش',
    'ladders': 'سلالم',
    'ladder': 'سلالم',
    'construction': 'بناء',
    'building supplies': 'بناء',
    'pumps': 'مضخات',
    'pump': 'مضخات',
    'offers': 'العروض',
    'offer': 'العروض',
    'sale': 'العروض',
    'discount': 'العروض',
    'new arrivals': 'وصل حديثاً',
    'new arrival': 'وصل حديثاً',
  };

  /// اسم عربي موحّد للواجهة (للشريط والتصفية).
  static String canonical(String? raw) {
    if (raw == null) return '';
    var t = raw.trim();
    if (t.isEmpty) return '';
    t = t.replaceAll(RegExp(r'\s+'), ' ');

    final lower = t.toLowerCase();
    final en = _englishToArabic[lower];
    if (en != null) return en;

    final ar = _arabicCanonical[t];
    if (ar != null) return ar;

    if (RegExp(r'[\u0600-\u06FF]').hasMatch(t)) {
      return t;
    }

    return t;
  }
}
