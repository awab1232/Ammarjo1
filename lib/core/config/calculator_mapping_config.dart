/// تصنيف مهمة الحاسبة لربط المنتجات.
enum QuantityJobKind {
  /// دهانات — رئيسي: عبوات دهان؛ مستلزمات: رول، فرش، شريط، غطاء.
  paints,

  /// بلاط/بورسلان — رئيسي: م² بلاط؛ مستلزمات: لاصق، ترويب، فواصل.
  flooring,

  /// عظم/خرسانة — رئيسي: أسمنت/حسب البند؛ مستلزمات: رمل، زلط، حديد.
  skeleton,

  /// بدون قواعد خاصة — يعتمد على كلمات نتيجة الحساب فقط.
  generic,
}

/// يحدد نوع المهمة من قسم JSON في حاسبة البناء.
QuantityJobKind quantityJobKindForCalculatorCategoryId(String calculatorCategoryId) {
  switch (calculatorCategoryId) {
    case 'national_paints_section':
    case 'golden_paints_section':
    case 'quds_paints_section':
      return QuantityJobKind.paints;
    case 'tile_adhesives_jordan':
      return QuantityJobKind.flooring;
    case 'skeleton_works':
      return QuantityJobKind.skeleton;
    default:
      return QuantityJobKind.generic;
  }
}

/// ربط حاسبة الكميات مع أقسام ووسوم WooCommerce (معرّفات من لوحة التحكم).
///
/// اضبط المعرفات حسب متجرك لتحسين جلب المستلزمات والمواد الرئيسية من الخادم.
abstract final class CalculatorMappingConfig {
  /// دهانات / عبوات دهان.
  static const int? wcCategoryPaints = null;

  /// أدوات دهان: رول، فرش، شريط، تغطية.
  static const int? wcCategoryPaintTools = null;

  /// بلاط / بورسلان / سيراميك.
  static const int? wcCategoryTiles = null;

  /// لاصق بلاط، ترويب، فواصل.
  static const int? wcCategoryTileMaterials = null;

  /// أسمنت وإسمنت.
  static const int? wcCategoryCement = null;

  /// رمل وزلط وحصى.
  static const int? wcCategoryAggregates = null;

  /// حديد تسليح.
  static const int? wcCategorySteel = null;

  /// وسوم المنتجات: مستلزمات حاسبة / أدوات تركيب (اختياري).
  static const int? wcTagCalculatorEssentials = null;

  /// أقسام تُجلب ديناميكياً حسب نوع المهمة (بدون تكرار null).
  static List<int> wooCategoryIdsForJob(QuantityJobKind job) {
    switch (job) {
      case QuantityJobKind.paints:
        return [wcCategoryPaints, wcCategoryPaintTools].whereType<int>().toList();
      case QuantityJobKind.flooring:
        return [wcCategoryTiles, wcCategoryTileMaterials].whereType<int>().toList();
      case QuantityJobKind.skeleton:
        return [wcCategoryCement, wcCategoryAggregates, wcCategorySteel].whereType<int>().toList();
      case QuantityJobKind.generic:
        return <int>[];
    }
  }

  static int? tagIdForJob(QuantityJobKind job) {
    if (job == QuantityJobKind.generic) return null;
    return wcTagCalculatorEssentials;
  }
}
