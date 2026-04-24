import '../../store/domain/models.dart';

/// منتج داخل متجر (مصدر البيانات: PostgreSQL عبر REST).
class StoreShelfProduct {
  StoreShelfProduct({
    required this.id,
    required this.storeId,
    this.catalogProductId,
    required this.name,
    required this.description,
    required this.priceDisplay,
    required this.shelfCategory,
    required this.imageUrls,
    this.isAvailable = true,
    this.isPurchasable = true,
  });

  final String id;
  final String storeId;
  /// Filled from API when a `catalog_products` row matches this store + product name; required for server cart.
  final int? catalogProductId;
  final String name;
  final String description;
  final String priceDisplay;
  /// تبويب العرض (مثلاً «سباكة»، «الكل» يطابق الجميع).
  final String shelfCategory;
  final List<String> imageUrls;
  final bool isAvailable;
  final bool isPurchasable;

  /// If non-null, add-to-cart is blocked: show this in UI before calling [toCartProduct].
  static const String kCatalogProductUnavailable = 'المنتج غير متاح حالياً';

  String? get addToCartIfUnavailableMessage =>
      (catalogProductId == null || catalogProductId! <= 0) ? kCatalogProductUnavailable : null;

  factory StoreShelfProduct.fromBackendRow(
    String storeId,
    Map<String, dynamic> row, {
    String shelfCategory = 'عام',
  }) {
    final urls = <String>[];
    final primaryImage = (row['image'] ?? row['imageUrl'] ?? '').toString().trim();
    if (primaryImage.isNotEmpty) {
      urls.add(primaryImage);
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
    final stock = (row['stock'] ?? 0);
    final rawCatalog = row['catalogProductId'] ?? row['catalog_product_id'];
    int? catId;
    if (rawCatalog != null) {
      if (rawCatalog is int) {
        catId = rawCatalog;
      } else if (rawCatalog is num) {
        catId = rawCatalog.toInt();
      } else {
        catId = int.tryParse(rawCatalog.toString());
      }
    }
    if (catId != null && catId <= 0) {
      catId = null;
    }
    return StoreShelfProduct(
      id: row['id']?.toString() ?? '',
      storeId: storeId,
      catalogProductId: catId,
      name: row['name']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      priceDisplay: priceStr,
      shelfCategory: shelfCategory,
      imageUrls: urls,
      isAvailable: true,
      isPurchasable: (stock is num ? stock.toInt() : int.tryParse(stock.toString()) ?? 0) > 0,
    );
  }

  Product toCartProduct() {
    final pid = catalogProductId;
    if (pid == null || pid <= 0) {
      return Product(
        id: 0,
        name: name,
        description: description,
        price: priceDisplay,
        images: imageUrls,
        categoryIds: const <int>[],
        stock: 0,
        stockStatus: 'outofstock',
      );
    }
    return Product(
      id: pid,
      name: name,
      description: description,
      price: priceDisplay,
      images: imageUrls,
      categoryIds: const <int>[],
      stock: isPurchasable ? 1 : 0,
      stockStatus: isPurchasable ? 'instock' : 'outofstock',
    );
  }
}
