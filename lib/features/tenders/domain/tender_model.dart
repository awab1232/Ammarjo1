class TenderModel {
  final String id;
  final String userId;
  final String userName;
  final String imageUrl;
  final List<String> imageUrls;
  final String categoryId;
  final String description;
  final String city;
  final String status; // open|accepted|expired|closed
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? acceptedOfferId;
  final List<TenderOffer> offers;

  TenderModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.imageUrl,
    required this.imageUrls,
    required this.categoryId,
    required this.description,
    required this.city,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedOfferId,
    this.offers = const <TenderOffer>[],
  });

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    try {
      final sec = (value as dynamic).seconds;
      if (sec is int) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    } on Object {
      // Use fallback parser below when timestamp shape is unknown.
    }
    return DateTime.tryParse(value.toString());
  }

  factory TenderModel.fromMap(String id, Map<String, dynamic> d) {
    final createdAt = _parseDate(d['createdAt']) ?? _parseDate(d['updatedAt']) ?? DateTime.now();
    final expiresAt = _parseDate(d['expiresAt']) ?? createdAt.add(const Duration(days: 7));
    final resolvedUserId = d['userId']?.toString() ?? '';
    final resolvedUserName = d['userName']?.toString() ?? d['customerName']?.toString() ?? 'مستخدم';
    final rawImages = (d['imageUrls'] is List) ? (d['imageUrls'] as List<dynamic>) : const <dynamic>[];
    final imageUrls = rawImages.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(growable: false);
    final imageUrl = d['imageUrl']?.toString() ?? (imageUrls.isNotEmpty ? imageUrls.first : '');
    return TenderModel(
      id: id,
      userId: resolvedUserId.isNotEmpty ? resolvedUserId : 'unknown',
      userName: resolvedUserName.trim().isNotEmpty ? resolvedUserName : 'مستخدم',
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      categoryId: d['categoryId']?.toString() ?? '',
      description: d['description']?.toString() ?? '',
      city: d['city']?.toString() ?? '',
      status: d['status']?.toString() ?? 'open',
      createdAt: createdAt,
      expiresAt: expiresAt,
      acceptedOfferId: d['acceptedOfferId']?.toString(),
      offers: const <TenderOffer>[],
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isOpen => status == 'open' && !isExpired;

  String get timeLeft {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'منتهية';
    if (diff.inHours > 0) return 'ينتهي بعد ${diff.inHours} ساعة';
    return 'ينتهي بعد ${diff.inMinutes} دقيقة';
  }
}

class TenderOffer {
  final String id;
  final String storeId;
  final String storeName;
  final String storeOwnerId;
  final double price;
  final String note;
  final DateTime createdAt;
  final String status; // pending|accepted|rejected

  TenderOffer({
    required this.id,
    required this.storeId,
    required this.storeName,
    required this.storeOwnerId,
    required this.price,
    required this.note,
    required this.createdAt,
    required this.status,
  });

  factory TenderOffer.fromMap(String id, Map<String, dynamic> d) {
    final parsedPrice = (d['price'] is num)
        ? (d['price'] as num).toDouble()
        : double.tryParse(d['price']?.toString() ?? '0') ?? 0;
    return TenderOffer(
      id: id,
      storeId: d['storeId']?.toString() ?? '',
      storeName: d['storeName']?.toString() ?? 'متجر',
      storeOwnerId: d['storeOwnerId']?.toString() ?? d['storeOwnerUid']?.toString() ?? '',
      price: parsedPrice,
      note: d['note']?.toString() ?? '',
      createdAt: TenderModel._parseDate(d['createdAt']) ?? DateTime.now(),
      status: d['status']?.toString() ?? 'pending',
    );
  }
}

/// صف في قائمة «عروض متجري» — عرض مُقدَّم + معرّف المناقصة الأم.
class StoreSubmittedOfferRow {
  StoreSubmittedOfferRow({
    required this.tenderId,
    required this.offer,
  });

  final String tenderId;
  final TenderOffer offer;

  factory StoreSubmittedOfferRow.fromMap(String tenderId, String offerId, Map<String, dynamic> data) {
    return StoreSubmittedOfferRow(
      tenderId: tenderId,
      offer: TenderOffer.fromMap(offerId, data),
    );
  }
}
