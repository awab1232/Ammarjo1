import 'models.dart';

/// صف مفضّلة في `users/{uid}/favorites/{productId}`.
class FavoriteProduct {
  const FavoriteProduct({
    required this.productId,
    this.addedAt,
    required this.productName,
    required this.productImage,
    required this.productPrice,
  });

  final String productId;
  final DateTime? addedAt;
  final String productName;
  final String productImage;
  final double productPrice;

  static DateTime? _parseAddedAt(dynamic ts) {
    if (ts == null) return null;
    try {
      final sec = (ts as dynamic).seconds;
      if (sec is int) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    } on Object {
      return DateTime.tryParse(ts.toString());
    }
    if (ts is DateTime) return ts;
    return DateTime.tryParse(ts.toString());
  }

  factory FavoriteProduct.fromMap(String docId, Map<String, dynamic> d) {
    return FavoriteProduct(
      productId: d['productId']?.toString() ?? docId,
      addedAt: _parseAddedAt(d['addedAt']),
      productName: d['productName']?.toString() ?? '',
      productImage: d['productImage']?.toString() ?? '',
      productPrice: (d['productPrice'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// لعرض تفاصيل المنتج عند الضغط (بيانات قد تكون أقل من كتالوج كامل).
  Product toMinimalProduct() {
    final id = int.tryParse(productId) ?? 0;
    final imgs = productImage.trim().isNotEmpty ? <String>[productImage.trim()] : <String>[];
    return Product(
      id: id,
      name: productName,
      description: '',
      price: productPrice.toString(),
      images: imgs,
      categoryIds: const [],
    );
  }
}
