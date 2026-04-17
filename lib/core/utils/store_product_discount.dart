/// منطق موحّد لسعر منتج المتجر بين واجهة الزائر ولوحة صاحب المتجر.
/// يدعم حقولاً اختيارية [discountStart] / [discountEnd] (Timestamp)؛ عند غيابها يُطبَّق
/// نفس شرط السعر المخفّض المستخدم سابقاً (سعر مخفّض أقل من الأساسي).
class StoreProductDiscountView {
  const StoreProductDiscountView({
    required this.basePrice,
    required this.effectivePrice,
    required this.hasActiveDiscount,
  });

  final double basePrice;
  final double effectivePrice;
  final bool hasActiveDiscount;

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      final sec = (value as dynamic).seconds;
      if (sec is int) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    } on Object {
      return DateTime.tryParse(value.toString());
    }
    return DateTime.tryParse(value.toString());
  }

  /// [m] بيانات منتج من `stores/{storeId}/products/{id}`.
  factory StoreProductDiscountView.fromProductMap(
    Map<String, dynamic> m, {
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final price = (m['price'] as num?)?.toDouble() ?? double.tryParse('${m['price'] ?? 0}') ?? 0.0;
    final rawDp = (m['discountPrice'] as num?)?.toDouble();

    var inDiscountWindow = true;
    final ds = m['discountStart'];
    final de = m['discountEnd'];
    final dsDate = _parseDate(ds);
    if (dsDate != null && n.isBefore(dsDate)) inDiscountWindow = false;
    final deDate = _parseDate(de);
    if (deDate != null && n.isAfter(deDate)) inDiscountWindow = false;

    final hasNumericDiscount =
        rawDp != null && rawDp > 0 && rawDp < price;
    final hasActiveDiscount = hasNumericDiscount && inDiscountWindow;

    return StoreProductDiscountView(
      basePrice: price,
      effectivePrice: hasActiveDiscount ? rawDp : price,
      hasActiveDiscount: hasActiveDiscount,
    );
  }
}
