class Coupon {
  Coupon({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.maxDiscount,
    required this.applicableProducts,
    required this.applicableStores,
    required this.excludedProducts,
    required this.excludedStores,
    required this.usageLimit,
    required this.usagePerUser,
    required this.usedCount,
    required this.validFrom,
    required this.validTo,
    required this.isActive,
    required this.isStackable,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final String description;
  final String discountType; // percentage | fixed
  final double discountValue;
  final double minOrderAmount;
  final double? maxDiscount;
  final List<int> applicableProducts;
  final List<String> applicableStores;
  final List<int> excludedProducts;
  final List<String> excludedStores;
  final int? usageLimit;
  final int usagePerUser;
  final int usedCount;
  final DateTime? validFrom;
  final DateTime? validTo;
  final bool isActive;
  final bool isStackable;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Coupon.fromMap(Map<String, dynamic> d) {
    DateTime? toDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    List<int> intList(dynamic v) => v is List
        ? v
            .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toList()
        : <int>[];
    List<String> strList(dynamic v) =>
        v is List ? v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() : <String>[];
    return Coupon(
      id: d['id']?.toString() ?? '',
      code: (d['code']?.toString() ?? '').trim().toUpperCase(),
      name: d['name']?.toString() ?? '',
      description: d['description']?.toString() ?? '',
      discountType: (d['discountType']?.toString() ?? 'percentage').trim(),
      discountValue: (d['discountValue'] as num?)?.toDouble() ?? 0,
      minOrderAmount: (d['minOrderAmount'] as num?)?.toDouble() ?? 0,
      maxDiscount: (d['maxDiscount'] as num?)?.toDouble(),
      applicableProducts: intList(d['applicableProducts']),
      applicableStores: strList(d['applicableStores']),
      excludedProducts: intList(d['excludedProducts']),
      excludedStores: strList(d['excludedStores']),
      usageLimit: (d['usageLimit'] as num?)?.toInt(),
      usagePerUser: (d['usagePerUser'] as num?)?.toInt() ?? 0,
      usedCount: (d['usedCount'] as num?)?.toInt() ?? 0,
      validFrom: toDate(d['validFrom']),
      validTo: toDate(d['validTo']),
      isActive: d['isActive'] == true,
      isStackable: d['isStackable'] == true,
      createdBy: d['createdBy']?.toString() ?? '',
      createdAt: toDate(d['createdAt']),
      updatedAt: toDate(d['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'code': code.trim().toUpperCase(),
        'name': name.trim(),
        'description': description.trim(),
        'discountType': discountType,
        'discountValue': discountValue,
        'minOrderAmount': minOrderAmount,
        if (maxDiscount != null) 'maxDiscount': maxDiscount,
        'applicableProducts': applicableProducts,
        'applicableStores': applicableStores,
        'excludedProducts': excludedProducts,
        'excludedStores': excludedStores,
        if (usageLimit != null) 'usageLimit': usageLimit,
        'usagePerUser': usagePerUser,
        'usedCount': usedCount,
        if (validFrom != null) 'validFrom': validFrom!.toUtc().toIso8601String(),
        if (validTo != null) 'validTo': validTo!.toUtc().toIso8601String(),
        'isActive': isActive,
        'isStackable': isStackable,
        'createdBy': createdBy,
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

  bool isValidNow() {
    if (!isActive) return false;
    final now = DateTime.now();
    if (validFrom != null && now.isBefore(validFrom!)) return false;
    if (validTo != null && now.isAfter(validTo!)) return false;
    if (usageLimit != null && usedCount >= usageLimit!) return false;
    return true;
  }

  bool isValid({
    required String userId,
    required double orderAmount,
    required List<int> productIds,
    required List<String> storeIds,
    required int userUsedCount,
  }) {
    if (!isValidNow()) return false;
    if (orderAmount < minOrderAmount) return false;
    if (usagePerUser > 0 && userUsedCount >= usagePerUser) return false;
    if (applicableProducts.isNotEmpty && !productIds.any(applicableProducts.contains)) return false;
    if (applicableStores.isNotEmpty && !storeIds.any(applicableStores.contains)) return false;
    if (excludedProducts.any(productIds.contains)) return false;
    if (excludedStores.any(storeIds.contains)) return false;
    return true;
  }

  double calculateDiscount({
    required double orderAmount,
  }) {
    if (orderAmount <= 0) return 0;
    double discount;
    if (discountType == 'fixed') {
      discount = discountValue;
    } else {
      discount = (orderAmount * discountValue) / 100;
      if (maxDiscount != null && discount > maxDiscount!) discount = maxDiscount!;
    }
    if (discount > orderAmount) discount = orderAmount;
    if (discount < 0) discount = 0;
    return discount;
  }
}

class CouponUsage {
  CouponUsage({
    required this.id,
    required this.couponCode,
    required this.userId,
    required this.userEmail,
    required this.orderId,
    required this.discountAmount,
    required this.orderAmount,
    required this.usedAt,
  });

  final String id;
  final String couponCode;
  final String userId;
  final String userEmail;
  final String orderId;
  final double discountAmount;
  final double orderAmount;
  final DateTime usedAt;

  factory CouponUsage.fromMap(Map<String, dynamic> d) {
    final ts = DateTime.tryParse(d['usedAt']?.toString() ?? '');
    return CouponUsage(
      id: d['id']?.toString() ?? '',
      couponCode: d['couponCode']?.toString() ?? '',
      userId: d['userId']?.toString() ?? '',
      userEmail: d['userEmail']?.toString() ?? '',
      orderId: d['orderId']?.toString() ?? '',
      discountAmount: (d['discountAmount'] as num?)?.toDouble() ?? 0,
      orderAmount: (d['orderAmount'] as num?)?.toDouble() ?? 0,
      usedAt: ts ?? DateTime.now(),
    );
  }
}

class CouponValidationResult {
  const CouponValidationResult({
    required this.isValid,
    required this.message,
    this.coupon,
    this.discountAmount = 0,
  });

  final bool isValid;
  final String message;
  final Coupon? coupon;
  final double discountAmount;
}
