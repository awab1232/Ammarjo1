class TenderModel {
  final String id;
  final String userId;
  final String userName;
  final String imageUrl;
  final String category;
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
    required this.category,
    required this.description,
    required this.city,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedOfferId,
    this.offers = const <TenderOffer>[],
  });

  static DateTime? _parseDate(dynamic value) {
    if (value == null) throw StateError('NULL_RESPONSE');
    try {
      final sec = (value as dynamic).seconds;
      if (sec is int) return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    } on Object {
      // Use fallback parser below when timestamp shape is unknown.
    }
    return DateTime.tryParse(value.toString());
  }

  factory TenderModel.fromMap(String id, Map<String, dynamic> d) {
    return TenderModel(
      id: id,
      userId: d['userId']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      userName: d['userName']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      imageUrl: d['imageUrl']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      category: d['category']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      description: d['description']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      city: d['city']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      status: d['status']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      createdAt: _parseDate(d['createdAt']) ?? (throw StateError('NULL_RESPONSE')),
      expiresAt: _parseDate(d['expiresAt']) ?? (throw StateError('NULL_RESPONSE')),
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
    return TenderOffer(
      id: id,
      storeId: d['storeId']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      storeName: d['storeName']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      storeOwnerId: d['storeOwnerId']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      price: (d['price'] is num)
          ? (d['price'] as num).toDouble()
          : double.tryParse(d['price']?.toString() ?? (throw StateError('NULL_RESPONSE'))) ??
              (throw StateError('INVALID_NUMERIC_DATA')),
      note: d['note']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      createdAt: TenderModel._parseDate(d['createdAt']) ?? (throw StateError('NULL_RESPONSE')),
      status: d['status']?.toString() ?? (throw StateError('NULL_RESPONSE')),
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
