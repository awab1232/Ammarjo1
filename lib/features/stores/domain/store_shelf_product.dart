import '../../store/domain/models.dart';

/// منتج داخل متجر (مصدر البيانات: PostgreSQL عبر REST).
class StoreShelfProduct {
  StoreShelfProduct({
    required this.id,
    required this.storeId,
    required this.name,
    required this.description,
    required this.priceDisplay,
    required this.shelfCategory,
    required this.imageUrls,
    this.isAvailable = true,
  });

  final String id;
  final String storeId;
  final String name;
  final String description;
  final String priceDisplay;
  /// تبويب العرض (مثلاً «سباكة»، «الكل» يطابق الجميع).
  final String shelfCategory;
  final List<String> imageUrls;
  final bool isAvailable;

  /// معرّف مستقر للسلة يعتمد على المتجر + وثيقة المنتج.
  int get cartProductId => Object.hash(storeId, id).abs();

  factory StoreShelfProduct.fromBackendRow(
    String storeId,
    Map<String, dynamic> row, {
    String shelfCategory = 'عام',
  }) {
    final urls = <String>[];
    if ((row['imageUrl']?.toString() ?? '').isNotEmpty) {
      urls.add(row['imageUrl'].toString());
    }
    final images = row['images'];
    if (images is List) {
      for (final x in images) {
        final s = x.toString();
        if (s.isNotEmpty) urls.add(s);
      }
    }
    final priceFromVariants = row['quantityPrices'] is List && (row['quantityPrices'] as List).isNotEmpty
        ? ((row['quantityPrices'] as List).first as Map)['price']?.toString() ?? ''
        : '';
    final priceStr = priceFromVariants.isNotEmpty
        ? priceFromVariants
        : (row['price'] is num
            ? (row['price'] as num).toString()
            : row['price']?.toString() ?? '0');
    final stock = (row['stock'] as num?)?.toInt() ?? 0;
    return StoreShelfProduct(
      id: row['id']?.toString() ?? '',
      storeId: storeId,
      name: row['name']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      priceDisplay: priceStr,
      shelfCategory: shelfCategory,
      imageUrls: urls,
      isAvailable: stock > 0,
    );
  }

  Product toCartProduct() {
    return Product(
      id: cartProductId,
      name: name,
      description: description,
      price: priceDisplay,
      images: imageUrls,
      categoryIds: const [],
    );
  }
}
