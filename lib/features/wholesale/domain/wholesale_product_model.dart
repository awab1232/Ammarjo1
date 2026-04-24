import 'quantity_price_tier.dart';

class WholesaleProduct {
  const WholesaleProduct({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.unit,
    required this.quantityPrices,
    required this.stock,
    this.categoryId,
    this.hasVariants = false,
    this.variants = const <WholesaleVariant>[],
  });

  final String productId;
  final String name;
  final String imageUrl;
  final String unit;
  final List<QuantityPriceTier> quantityPrices;
  final int stock;
  /// معرّف قسم من `wholesalers/{id}/categories/{categoryId}` — اختياري.
  final String? categoryId;
  final bool hasVariants;
  final List<WholesaleVariant> variants;

  factory WholesaleProduct.fromFirestore(Map<String, dynamic> data) {
    final tiersRaw = data['quantityPrices'];
    final tiers = <QuantityPriceTier>[];
    if (tiersRaw is List) {
      for (final row in tiersRaw) {
        if (row is Map) {
          tiers.add(QuantityPriceTier.fromFirestore(Map<String, dynamic>.from(row)));
        }
      }
    }
    final stockRaw = data['stock'];
    final rawCat = data['categoryId'] ?? data['wholesaleCategoryId'];
    final catStr = rawCat?.toString().trim() ?? (throw StateError('unexpected_empty_response'));
    return WholesaleProduct(
      productId: (data['productId'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      name: (data['name'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      imageUrl: (data['imageUrl'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      unit: (data['unit'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      quantityPrices: tiers,
      stock: stockRaw is num
          ? stockRaw.toInt()
          : int.tryParse(stockRaw?.toString() ?? (throw StateError('unexpected_empty_response'))) ??
              (throw StateError('INVALID_NUMERIC_DATA')),
      categoryId: catStr.isEmpty ? null : catStr,
      hasVariants: data['hasVariants'] == true || data['has_variants'] == true,
      variants: (data['variants'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((x) => WholesaleVariant.fromMap(Map<String, dynamic>.from(x)))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() => <String, dynamic>{
        'productId': productId,
        'name': name,
        'imageUrl': imageUrl,
        'unit': unit,
        'quantityPrices': quantityPrices.map((e) => e.toFirestore()).toList(),
        'stock': stock,
        'hasVariants': hasVariants,
        'variants': variants.map((e) => e.toMap()).toList(),
        if (categoryId != null && categoryId!.isNotEmpty) 'categoryId': categoryId,
      };
}

class WholesaleVariant {
  const WholesaleVariant({
    required this.id,
    required this.price,
    required this.stock,
    this.isDefault = false,
    this.options = const <Map<String, String>>[],
  });

  final String id;
  final double price;
  final int stock;
  final bool isDefault;
  final List<Map<String, String>> options;

  factory WholesaleVariant.fromMap(Map<String, dynamic> m) {
    return WholesaleVariant(
      id: m['id']?.toString() ?? (throw StateError('unexpected_empty_response')),
      price: (m['price'] as num?)?.toDouble() ??
          double.tryParse(m['price']?.toString() ?? (throw StateError('unexpected_empty_response'))) ??
          (throw StateError('INVALID_NUMERIC_DATA')),
      stock: (m['stock'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA')),
      isDefault: m['isDefault'] == true || m['is_default'] == true,
      options: (m['options'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((x) {
            final mm = Map<String, dynamic>.from(x);
            return {
              'optionType': mm['optionType']?.toString() ??
                  mm['option_type']?.toString() ??
                  (throw StateError('unexpected_empty_response')),
              'optionValue': mm['optionValue']?.toString() ??
                  mm['option_value']?.toString() ??
                  (throw StateError('unexpected_empty_response')),
            };
          })
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'price': price,
        'stock': stock,
        'isDefault': isDefault,
        'options': options,
      };
}
