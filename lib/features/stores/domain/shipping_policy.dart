class ShippingPolicy {
  const ShippingPolicy({
    required this.type,
    this.amount,
    this.freeShippingThreshold,
    this.estimatedDays,
  });

  final String type; // fixed | free | percentage | perItem
  final num? amount;
  final num? freeShippingThreshold;
  final int? estimatedDays;

  static const ShippingPolicy defaults = ShippingPolicy(
    type: 'fixed',
    amount: 2.0,
  );

  factory ShippingPolicy.fromMap(Map<String, dynamic>? map) {
    if (map == null) return defaults;
    final type = (map['type']?.toString().trim().toLowerCase() ?? 'fixed');
    return ShippingPolicy(
      type: type.isEmpty ? 'fixed' : type,
      amount: _toNum(map['amount']),
      freeShippingThreshold: _toNum(map['freeShippingThreshold']),
      estimatedDays: _toInt(map['estimatedDays']),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        if (amount != null) 'amount': amount,
        if (freeShippingThreshold != null) 'freeShippingThreshold': freeShippingThreshold,
        if (estimatedDays != null) 'estimatedDays': estimatedDays,
      };

  double calculateShipping({
    required double subtotal,
    required int itemCount,
  }) {
    final safeSubtotal = subtotal < 0 ? 0.0 : subtotal;
    final safeCount = itemCount < 0 ? 0 : itemCount;
    switch (type) {
      case 'free':
        return 0;
      case 'percentage':
        final pct = (amount ?? 0).toDouble();
        final fee = safeSubtotal * (pct / 100.0);
        final threshold = (freeShippingThreshold ?? 0).toDouble();
        if (threshold > 0 && safeSubtotal >= threshold) return 0;
        return fee < 0 ? 0.0 : fee;
      case 'perItem':
        final per = (amount ?? 0).toDouble();
        final fee = per * safeCount;
        return fee < 0 ? 0.0 : fee;
      case 'fixed':
      default:
        final threshold = (freeShippingThreshold ?? 0).toDouble();
        if (threshold > 0 && safeSubtotal >= threshold) return 0;
        final fee = (amount ?? 2.0).toDouble();
        return fee < 0 ? 0.0 : fee;
    }
  }

  static num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
