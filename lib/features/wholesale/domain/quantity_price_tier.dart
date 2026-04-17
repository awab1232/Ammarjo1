class QuantityPriceTier {
  const QuantityPriceTier({
    required this.minQuantity,
    required this.price,
  });

  final int minQuantity;
  final double price;

  factory QuantityPriceTier.fromFirestore(Map<String, dynamic> data) {
    final mq = data['minQuantity'];
    final p = data['price'];
    return QuantityPriceTier(
      minQuantity: mq is num ? mq.toInt() : int.tryParse(mq?.toString() ?? '') ?? 1,
      price: p is num ? p.toDouble() : double.tryParse(p?.toString() ?? '') ?? 0.0,
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
        'minQuantity': minQuantity,
        'price': price,
      };
}
