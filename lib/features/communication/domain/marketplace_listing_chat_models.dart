import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/jordan_phone.dart';

/// بريد الطرف البائع للمحادثة — من `ownerEmail` أو اصطناعي من رقم الهاتف.
/// (بيانات قديمة من مجموعة `used_items` للمحادثات المؤرشفة.)
String resolvePeerEmailForListing(MarketplaceListing l) {
  final o = l.ownerEmail?.trim();
  if (o != null && o.isNotEmpty) return o;
  final u = normalizeJordanPhoneForUsername(l.phone);
  if (u.length >= 12 && u.startsWith('962')) {
    return syntheticEmailForPhone(u);
  }
  return 'listing_${l.id}@marketplace.ammarjo.app';
}

/// فئات قديمة لإعلانات مستعملة (للتوافق مع بيانات قديمة).
class MarketplaceCategory {
  const MarketplaceCategory({required this.id, required this.labelAr});

  final String id;
  final String labelAr;

  static const List<MarketplaceCategory> all = [
    MarketplaceCategory(id: 'electric_used', labelAr: 'عدد كهربائية'),
    MarketplaceCategory(id: 'hand_used', labelAr: 'عدد يدوية'),
    MarketplaceCategory(id: 'workshop_leftovers', labelAr: 'زوايد ورشة'),
    MarketplaceCategory(id: 'wood_tobar', labelAr: 'خشب طوبار'),
    MarketplaceCategory(id: 'other_tools', labelAr: 'أدوات أخرى'),
  ];

  static String labelForId(String id) {
    for (final c in all) {
      if (c.id == id) return c.labelAr;
    }
    return id;
  }
}

/// لقطة إعلان قديمة (مجموعة `used_items`) — للمحادثات والأرشيف فقط.
class MarketplaceListing {
  MarketplaceListing({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.description,
    required this.priceLabel,
    required this.conditionLabel,
    required this.phone,
    required this.city,
    this.imageUrl,
    this.imageUrls = const [],
    this.imageBase64,
    required this.createdAt,
    this.ownerEmail,
    this.sellerId,
    this.listingStatus = 'active',
  });

  final String id;
  final String categoryId;
  final String title;
  final String description;
  final String priceLabel;
  final String conditionLabel;
  final String phone;
  final String city;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? imageBase64;
  final DateTime createdAt;
  final String? ownerEmail;
  final String? sellerId;
  final String listingStatus;

  factory MarketplaceListing.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    DateTime created = DateTime.now();
    final ct = d['createdAt'];
    if (ct is Timestamp) {
      created = ct.toDate();
    }
    final urls = <String>[];
    final rawUrls = d['image_urls'] ?? d['imageUrls'];
    if (rawUrls is List) {
      for (final e in rawUrls) {
        final s = e.toString().trim();
        if (s.isNotEmpty) urls.add(s);
      }
    }
    final legacy = d['imageUrl'] as String?;
    if (urls.isEmpty && legacy != null && legacy.isNotEmpty) {
      urls.add(legacy);
    }
    final price = d['price'];
    final priceLabel = price is num ? price.toString() : (price?.toString() ?? '');
    var listingStatus = (d['status'] as String?)?.trim().toLowerCase() ?? '';
    if (listingStatus.isEmpty) listingStatus = 'active';
    return MarketplaceListing(
      id: doc.id,
      categoryId: d['category'] as String? ?? '',
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      priceLabel: priceLabel,
      conditionLabel: d['conditionLabel'] as String? ?? 'مستعمل',
      phone: d['phone'] as String? ?? '',
      city: d['city'] as String? ?? 'غير محدد',
      imageUrl: urls.isNotEmpty ? urls.first : legacy,
      imageUrls: urls,
      imageBase64: null,
      createdAt: created,
      ownerEmail: d['ownerEmail'] as String?,
      sellerId: d['seller_id'] as String?,
      listingStatus: listingStatus,
    );
  }
}
