class MarketplaceProduct {
  final String id;
  final String name;
  final String? image;
  final double price;
  final String storeId;
  final String subCategoryId;

  const MarketplaceProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.storeId,
    required this.subCategoryId,
    this.image,
  });

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final storeId = (json['store_id'] ?? json['storeId'])?.toString().trim() ?? '';
    final subCategoryId = (json['sub_category_id'] ?? json['subCategoryId'])?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty || storeId.isEmpty || subCategoryId.isEmpty) {
      throw const FormatException('INVALID_MARKETPLACE_PRODUCT_PAYLOAD');
    }
    final priceRaw = json['price'];
    if (priceRaw == null) {
      throw StateError('INVALID_PRICE');
    }
    final price = switch (priceRaw) {
      num value => value.toDouble(),
      String value => double.tryParse(value),
      _ => null,
    };
    if (price == null) {
      throw StateError('INVALID_PRICE');
    }
    return MarketplaceProduct(
      id: id,
      name: name,
      price: price,
      storeId: storeId,
      subCategoryId: subCategoryId,
      image: json['image']?.toString(),
    );
  }
}
