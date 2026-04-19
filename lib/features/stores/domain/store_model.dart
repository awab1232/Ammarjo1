import '../../../core/constants/jordan_regions.dart';
import 'shipping_policy.dart';
import 'store_opening_hours.dart';

/// متجر من واجهة REST (PostgreSQL عبر orders API).
class StoreModel {
  final String id;
  final String ownerId;
  final String name;
  final String phone;
  final String description;
  final String category;
  /// نطاق البيع: `city` (مدينة رئيسية) أو `all_jordan` (كل المملكة).
  final String? sellScope;
  /// المدينة الرئيسية عند [sellScope] == `city`.
  final String? city;
  /// مدن الخدمة، مثل `['عمان','الزرقاء']` أو `['all']` لجميع المحافظات — يُحتفَى بها للتوافق مع البيانات القديمة.
  final List<String> cities;
  /// `pending` | `approved` | `rejected`
  final String status;
  final String coverImage;
  final String logo;
  final double rating;
  final int reviewCount;
  final DateTime createdAt;
  /// عروض ترويجية نشطة (شارة في القائمة).
  final bool hasOffers;
  final bool hasActivePromotions;
  final bool hasDiscountedProducts;
  final bool freeDelivery;
  /// متجر مميز (priority exposure in home sections).
  final bool isFeatured;
  final bool isBoosted;
  final DateTime? boostExpiresAt;
  final String? storeTypeId;
  final String? storeTypeKey;
  /// Unified business type for dashboard/marketplace split: `retail` | `wholesale`.
  final String storeType;
  /// وقت توصيل تقريبي للعرض (نص حر من لوحة المتجر).
  final String deliveryTime;
  final ShippingPolicy shippingPolicy;
  /// المتجر يوفّر توصيلاً بسواقيه؛ `false` = لا يوجد توصيل.
  final bool hasOwnDrivers;
  /// رسوم التوصيل من الخادم (دينار).
  final double? deliveryFee;
  /// حد أدنى للطلب لشحن مجاني.
  final double? freeDeliveryMinOrder;
  /// محافظات التوصيل؛ فارغ = كل الأردن.
  final List<String> deliveryAreas;
  /// أوقات العمل؛ إن وُجدت ومفعّلة يُستخدم [StoreWeeklyHours.isOpenNow] لعرض «مغلق الآن».
  final StoreWeeklyHours? openingHours;

  StoreModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.phone,
    required this.description,
    required this.category,
    this.sellScope,
    this.city,
    required this.cities,
    required this.status,
    this.coverImage = '',
    this.logo = '',
    this.rating = 0.0,
    this.reviewCount = 0,
    required this.createdAt,
    this.hasOffers = false,
    this.hasActivePromotions = false,
    this.hasDiscountedProducts = false,
    this.freeDelivery = false,
    this.isFeatured = false,
    this.isBoosted = false,
    this.boostExpiresAt,
    this.storeTypeId,
    this.storeTypeKey,
    this.storeType = 'retail',
    this.deliveryTime = '',
    this.shippingPolicy = ShippingPolicy.defaults,
    this.hasOwnDrivers = true,
    this.deliveryFee,
    this.freeDeliveryMinOrder,
    this.deliveryAreas = const <String>[],
    this.openingHours,
  });

  factory StoreModel.fromBackendMap(Map<String, dynamic> raw) {
    DateTime createdAt = DateTime.now();
    final createdRaw = raw['createdAt']?.toString();
    if (createdRaw != null && createdRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(createdRaw) ?? createdAt;
    }
    final city = raw['city']?.toString().trim() ?? '';
    return StoreModel(
      id: raw['id']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      ownerId: raw['ownerId']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      name: raw['name']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      phone: raw['phone']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      description: raw['description']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      category: raw['category']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      sellScope: city.isEmpty ? 'all_jordan' : 'city',
      city: city.isEmpty ? null : city,
      cities: city.isEmpty ? const ['all'] : <String>[city],
      status: raw['status']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      coverImage: raw['coverImage']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      logo: raw['logo']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      rating: (raw['rating'] as num?)?.toDouble() ?? (throw StateError('INVALID_NUMERIC_DATA')),
      reviewCount: (raw['reviewCount'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA')),
      createdAt: createdAt,
      hasOffers: raw['hasOffers'] == true || raw['hasActivePromotions'] == true || raw['has_active_promotions'] == true,
      hasActivePromotions: raw['hasActivePromotions'] == true || raw['has_active_promotions'] == true,
      hasDiscountedProducts: raw['hasDiscountedProducts'] == true || raw['has_discounted_products'] == true,
      freeDelivery: raw['freeDelivery'] == true || raw['free_delivery'] == true,
      isFeatured: raw['isFeatured'] == true || raw['is_featured'] == true,
      isBoosted: raw['isBoosted'] == true || raw['is_boosted'] == true,
      boostExpiresAt: DateTime.tryParse(raw['boostExpiresAt']?.toString() ?? raw['boost_expires_at']?.toString() ?? ''),
      storeTypeId: raw['storeTypeId']?.toString() ?? raw['store_type_id']?.toString(),
      storeTypeKey: raw['storeTypeKey']?.toString() ?? raw['store_type_key']?.toString(),
      storeType: _resolveStoreType(
        raw['storeType']?.toString(),
        raw['storeTypeKey']?.toString() ?? raw['store_type_key']?.toString(),
      ),
      deliveryTime: raw['deliveryTime']?.toString().trim() ?? raw['delivery_time']?.toString().trim() ?? '',
      shippingPolicy: ShippingPolicy.fromMap(
        raw['shippingPolicy'] is Map ? Map<String, dynamic>.from(raw['shippingPolicy'] as Map) : null,
      ),
      hasOwnDrivers: !(raw['hasOwnDrivers'] == false || raw['has_own_drivers'] == false),
      deliveryFee: _readDouble(raw['deliveryFee'] ?? raw['delivery_fee']),
      freeDeliveryMinOrder: _readDouble(raw['freeDeliveryMinOrder'] ?? raw['free_delivery_min_order']),
      deliveryAreas: _stringList(raw['deliveryAreas'] ?? raw['delivery_areas']),
      openingHours: StoreWeeklyHours.tryParse(raw['openingHours'] ?? raw['opening_hours']),
    );
  }

  static double? _readDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
  }

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'name': name,
        'phone': phone,
        'description': description,
        'category': category,
        if (sellScope != null) 'sellScope': sellScope,
        if (city != null && city!.trim().isNotEmpty) 'city': city!.trim(),
        'cities': cities,
        'status': status,
        'coverImage': coverImage,
        'logo': logo,
        'rating': rating,
        'reviewCount': reviewCount,
        'createdAt': createdAt.toIso8601String(),
        'hasOffers': hasOffers,
        'hasActivePromotions': hasActivePromotions,
        'hasDiscountedProducts': hasDiscountedProducts,
        'freeDelivery': freeDelivery,
        'isFeatured': isFeatured,
        'isBoosted': isBoosted,
        if (boostExpiresAt != null) 'boostExpiresAt': boostExpiresAt!.toIso8601String(),
        if (storeTypeId != null) 'storeTypeId': storeTypeId,
        if (storeTypeKey != null) 'storeTypeKey': storeTypeKey,
        'storeType': storeType,
        if (deliveryTime.isNotEmpty) 'deliveryTime': deliveryTime,
        'shippingPolicy': shippingPolicy.toMap(),
        'hasOwnDrivers': hasOwnDrivers,
        if (deliveryFee != null) 'deliveryFee': deliveryFee,
        if (freeDeliveryMinOrder != null) 'freeDeliveryMinOrder': freeDeliveryMinOrder,
        'deliveryAreas': deliveryAreas,
        if (openingHours != null) 'openingHours': openingHours!.toJson(),
      };

  /// هل يصل المتجر للعميل في [customerCity] (بعد تطبيع المحافظة).
  bool deliversToCustomerCity(String? customerCity) {
    if (!hasOwnDrivers) return false;
    if (shippingPolicy.type == 'none') return false;
    final c = matchJordanRegion(customerCity?.trim() ?? '') ?? customerCity?.trim() ?? '';
    if (c.isEmpty) return true;
    if (deliveryAreas.isEmpty) return true;
    if (deliveryAreas.contains('كل الأردن')) return true;
    for (final a in deliveryAreas) {
      final ma = matchJordanRegion(a) ?? a;
      if (ma == c || a == c) return true;
    }
    return false;
  }
}

String _resolveStoreType(String? explicitType, String? storeTypeKey) {
  final t = (explicitType ?? '').trim().toLowerCase();
  if (t == 'retail' || t == 'wholesale') return t;
  final key = (storeTypeKey ?? '').trim().toLowerCase();
  if (key.contains('wholesale') || key.contains('jmla')) return 'wholesale';
  return 'retail';
}

/// اسم المتجر في الكتالوج الرئيسي (مجموعة `products`).
const String kAmmarJoCatalogStoreName = 'متجر عمار جو';

/// نموذج اصطناعي لبطاقة كتالوج عمار جو في قوائم المتاجر.
StoreModel ammarJoCatalogStoreModel() {
  return StoreModel(
    id: 'ammarjo',
    ownerId: '',
    name: kAmmarJoCatalogStoreName,
    phone: '',
    description: 'الكتالوج الرئيسي لمواد البناء والتشييد والسباكة والدهانات والأدوات.',
    category: 'مواد بناء',
    cities: const ['all'],
    status: 'approved',
    rating: 4.8,
    reviewCount: 0,
    createdAt: DateTime.utc(2020, 1, 1),
    hasActivePromotions: false,
    hasDiscountedProducts: false,
    freeDelivery: false,
    deliveryTime: '',
    openingHours: null,
  );
}
