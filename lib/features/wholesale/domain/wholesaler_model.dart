import 'wholesale_product_model.dart';

class WholesalerModel {
  const WholesalerModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.logo,
    required this.coverImage,
    required this.description,
    required this.category,
    required this.city,
    required this.phone,
    required this.email,
    required this.status,
    required this.commission,
    required this.products,
    required this.createdAt,
    this.approvedAt,
    this.approvedBy,
    this.deliveryDays,
    this.deliveryFee,
  });

  final String id;
  final String ownerId;
  final String name;
  final String logo;
  final String coverImage;
  final String description;
  final String category;
  final String city;
  final String phone;
  final String email;
  final String status; // pending | approved | rejected
  final double commission;
  final List<WholesaleProduct> products;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final String? approvedBy;
  /// مدة التوصيل بالأيام (عرض للمتاجر).
  final int? deliveryDays;
  /// رسوم التوصيل بالدينار.
  final double? deliveryFee;

  factory WholesalerModel.fromBackendMap(Map<String, dynamic> data) {
    final productsRaw = data['products'];
    final parsedProducts = <WholesaleProduct>[];
    if (productsRaw is List) {
      for (final row in productsRaw) {
        if (row is Map) {
          parsedProducts.add(
            WholesaleProduct.fromFirestore(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    final created = data['createdAt'];
    final approved = data['approvedAt'];
    final commissionRaw = data['commission'];
    final dd = data['deliveryDays'];
    final df = data['deliveryFee'];
    return WholesalerModel(
      id: (data['id'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      ownerId: (data['ownerId'] ?? data['owner_id'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      name: (data['name'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      logo: (data['logo'] ?? data['logoUrl'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      coverImage: (data['coverImage'] ?? data['cover_image'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      description: (data['description'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      category: (data['category'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      city: (data['city'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      phone: (data['phone'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      email: (data['email'] ?? (throw StateError('unexpected_empty_response'))).toString(),
      status: (data['status'] ?? 'pending').toString(),
      commission: commissionRaw is num
          ? commissionRaw.toDouble()
          : double.tryParse(commissionRaw?.toString() ?? (throw StateError('unexpected_empty_response'))) ??
              (throw StateError('INVALID_NUMERIC_DATA')),
      products: parsedProducts,
      createdAt: created is String ? (DateTime.tryParse(created)?.toLocal() ?? DateTime.now()) : DateTime.now(),
      approvedAt: approved is String ? DateTime.tryParse(approved)?.toLocal() : null,
      approvedBy: data['approvedBy']?.toString() ?? data['approved_by']?.toString(),
      deliveryDays: dd is num ? dd.toInt() : int.tryParse(dd?.toString() ?? ''),
      deliveryFee: df is num ? df.toDouble() : double.tryParse(df?.toString() ?? ''),
    );
  }
}
