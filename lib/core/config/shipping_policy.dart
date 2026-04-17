/// سياسة الشحن الافتراضية والقابلة للتعديل من لوحة الإدارة (`store_settings/shipping`).
class ShippingPolicy {
  const ShippingPolicy({
    required this.flatFeeJod,
    required this.freeThresholdJod,
    required this.freeShippingPromoEnabled,
  });

  /// رسوم ثابتة بالدينار عندما لا يطبق الإعفاء.
  final double flatFeeJod;

  /// إجمالي سلة المنتجات (قبل الشحن) الأعلى من هذا المبلغ → شحن مجاني (إن وُفعت العروض).
  final double freeThresholdJod;

  /// عند `false` تُفرض دائماً [flatFeeJod] (لتعطيل عروض الشحن المجاني من الأدمن).
  final bool freeShippingPromoEnabled;

  static const ShippingPolicy defaults = ShippingPolicy(
    flatFeeJod: 2.0,
    freeThresholdJod: 25.0,
    freeShippingPromoEnabled: true,
  );

  factory ShippingPolicy.fromMap(Map<String, dynamic> map) {
    return ShippingPolicy(
      flatFeeJod: _readDouble(map['flatFeeJod']) ?? defaults.flatFeeJod,
      freeThresholdJod: _readDouble(map['freeThresholdJod']) ?? defaults.freeThresholdJod,
      freeShippingPromoEnabled: map['freeShippingPromoEnabled'] is bool
          ? map['freeShippingPromoEnabled'] as bool
          : (map['freeShippingPromoEnabled']?.toString().toLowerCase() != 'false'),
    );
  }

  Map<String, dynamic> toMap() => {
        'flatFeeJod': flatFeeJod,
        'freeThresholdJod': freeThresholdJod,
        'freeShippingPromoEnabled': freeShippingPromoEnabled,
      };

  static double? _readDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// [cartSubtotal] = مجموع أسعار البضائع فقط (بدون شحن).
  double shippingForCartSubtotal(double cartSubtotal) {
    if (!freeShippingPromoEnabled) return flatFeeJod;
    if (cartSubtotal > freeThresholdJod) return 0;
    return flatFeeJod;
  }
}
