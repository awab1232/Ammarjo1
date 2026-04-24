class Product {
  final int id;
  final String name;
  final String description;
  final String price;
  final List<String> images;
  final List<int> categoryIds;
  /// معرفات وسوم WooCommerce (للتصفية والربط الذكي).
  final List<int> tagIds;

  /// نص التصنيف من Firestore (`category` / `categoryName`).
  final String? categoryField;

  /// نص التصنيف الفرعي من Firestore (`subCategory` / `subCategoryName`).
  final String? subCategoryField;

  /// وقت الإنشاء في Firestore (لترتيب «وصل حديثاً»).
  final DateTime? createdAtFirestore;

  /// كمية المخزون؛ `-1` يعني عدم تتبع سقف (منتجات قديمة بلا حقل).
  final int stock;

  /// مطابق لـ WooCommerce: `instock` | `outofstock` | `onbackorder`
  final String stockStatus;
  final bool hasVariants;
  final List<ProductVariant> variants;
  final bool isBoosted;
  final bool isTrending;

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.images,
    required this.categoryIds,
    List<int>? tagIds,
    this.categoryField,
    this.subCategoryField,
    this.createdAtFirestore,
    this.stock = -1,
    this.stockStatus = 'instock',
    this.hasVariants = false,
    this.variants = const <ProductVariant>[],
    this.isBoosted = false,
    this.isTrending = false,
  }) : tagIds = tagIds == null ? const <int>[] : tagIds;

  /// عرض توفر الشراء في واجهة المتجر (مع احترام `-1` ككمية غير محدودة).
  bool get isAvailableForPurchase {
    final s = stockStatus.trim().toLowerCase();
    if (s == 'outofstock') return false;
    if (stock < 0) return true;
    return stock > 0;
  }

  /// وصف للعرض في الواجهة؛ إن وُجد الحقل فارغاً في Firestore يُعرض نص بديل.
  String get displayDescription {
    final t = description.trim();
    if (t.isEmpty) return 'No description available';
    return t;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawImagesField = json['images'];
    final List<dynamic> rawImages;
    if (rawImagesField is List) {
      rawImages = rawImagesField;
    } else if (rawImagesField is String && rawImagesField.trim().isNotEmpty) {
      rawImages = [rawImagesField.trim()];
    } else {
      rawImages = <dynamic>[];
    }
    final rawCategories = (json['categories'] as List<dynamic>? ?? <dynamic>[]);
    final idVal = json['id'];
    final id = idVal is int
        ? idVal
        : idVal is num
            ? idVal.toInt()
            : int.tryParse(idVal?.toString() ?? '') ?? 0;

    final images = <String>[];
    for (final e in rawImages) {
      if (e is Map<String, dynamic>) {
        final src = e['src']?.toString();
        if (src != null && src.isNotEmpty) images.add(src);
      } else if (e is String && e.trim().isNotEmpty) {
        images.add(e.trim());
      }
    }

    final categoryIds = <int>[];
    for (final e in rawCategories) {
      if (e is Map<String, dynamic>) {
        final cid = e['id'];
        final n = cid is int
            ? cid
            : cid is num
                ? cid.toInt()
                : int.tryParse(cid?.toString() ?? '') ?? 0;
        if (n > 0) categoryIds.add(n);
      }
    }

    final tagIds = <int>[];
    final rawTags = json['tags'] as List<dynamic>? ?? <dynamic>[];
    for (final e in rawTags) {
      if (e is Map<String, dynamic>) {
        final tid = e['id'];
        final n = tid is int
            ? tid
            : tid is num
                ? tid.toInt()
                : int.tryParse(tid?.toString() ?? '') ?? 0;
        if (n > 0) tagIds.add(n);
      }
    }

    DateTime? parseCreated(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final stockRaw = json['stock'] ?? json['stock_quantity'];
    final stockVal = stockRaw is num
        ? stockRaw.toInt()
        : int.tryParse(stockRaw?.toString() ?? '') ?? -1;
    var ss = (json['stockStatus'] ?? json['stock_status'] ?? 'instock').toString().trim().toLowerCase();
    if (!const {'instock', 'outofstock', 'onbackorder'}.contains(ss)) {
      ss = 'instock';
    }

    return Product(
      id: id,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      price: _priceFromProductJson(json),
      images: images,
      categoryIds: categoryIds,
      tagIds: tagIds,
      categoryField: json['categoryField']?.toString(),
      subCategoryField: json['subCategoryField']?.toString(),
      createdAtFirestore: parseCreated(json['createdAtFirestore']),
      stock: stockVal,
      stockStatus: ss,
      hasVariants: json['hasVariants'] == true,
      variants: (json['variants'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((x) => ProductVariant.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
      isBoosted: json['isBoosted'] == true || json['is_boosted'] == true,
      isTrending: json['isTrending'] == true || json['is_trending'] == true,
    );
  }

  /// Matches WooCommerce REST: `price` (current), then `regular_price`, then variable `min_price`/`max_price`.
  static String _priceFromProductJson(Map<String, dynamic> json) {
    String pick(String key) => json[key]?.toString().trim() ?? '';

    var p = pick('price');
    if (p.isNotEmpty) return p;

    p = pick('regular_price');
    if (p.isNotEmpty) return p;

    final sale = pick('sale_price');
    if (sale.isNotEmpty) return sale;

    final min = pick('min_price');
    final max = pick('max_price');
    if (min.isNotEmpty && max.isNotEmpty) {
      if (min == max) return min;
      return '$min–$max';
    }
    if (min.isNotEmpty) return min;

    return '';
  }
}

/// WooCommerce product category (avoid name clash with Flutter's `Category` annotation).
class ProductCategory {
  final int id;
  final String name;
  final String imageUrl;
  /// WooCommerce `parent` — `0` للقسم الرئيسي.
  final int parent;
  /// صفحة العرض في التطبيق — حقل Firestore `page`: `home` | `stores` | `marketplace` | `technicians`.
  final String categoryPage;

  const ProductCategory({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.parent = 0,
    this.categoryPage = 'home',
  });

  bool visibleOnPage(String page) => categoryPage == page;

  factory ProductCategory.fromJson(Map<String, dynamic> json) {
    final idVal = json['id'];
    final id = idVal is int
        ? idVal
        : idVal is num
            ? idVal.toInt()
            : int.tryParse(idVal?.toString() ?? '') ?? 0;
    String imageUrl = '';
    final img = json['image'];
    if (img is Map<String, dynamic>) {
      imageUrl = img['src']?.toString() ?? '';
    }
    final parentVal = json['parent'];
    final parent = parentVal is int
        ? parentVal
        : parentVal is num
            ? parentVal.toInt()
            : int.tryParse(parentVal?.toString() ?? '') ?? 0;
    final pageRaw = json['page']?.toString().trim() ?? '';
    return ProductCategory(
      id: id,
      name: json['name']?.toString() ?? '',
      imageUrl: imageUrl,
      parent: parent,
      categoryPage: pageRaw.isEmpty ? 'home' : pageRaw,
    );
  }
}

class CartItem {
  final Product product;
  int quantity;
  final ProductVariant? selectedVariant;

  /// Server cart line id (NestJS `cart_items.id`) when using backend cart.
  String? backendLineId;

  /// معرف المتجر؛ الكتالوج الرئيسي يستخدم `ammarjo`.
  final String storeId;

  /// اسم المتجر للعرض وتجميع السلة.
  final String storeName;

  /// صورة سطر السلة (تُنسخ من المنتج عند الإضافة).
  final String imageUrl;
  final bool isTender;
  final String? tenderId;
  final String? tenderImageUrl;

  /// سطر من سوق الجملة (سلة الجملة المنفصلة تستخدم [WholesaleCartItem] غالباً).
  final bool isWholesale;
  final int? minQuantity;

  CartItem({
    required this.product,
    required this.quantity,
    this.backendLineId,
    this.storeId = 'ammarjo',
    this.storeName = 'متجر عمار جو',
    String? imageUrl,
    this.isTender = false,
    this.tenderId,
    this.tenderImageUrl,
    this.isWholesale = false,
    this.minQuantity,
    this.selectedVariant,
  }) : imageUrl = imageUrl ?? defaultImageUrlForProduct(product);

  factory CartItem.tenderOffer({
    required String tenderId,
    required String category,
    required double price,
    required String storeId,
    required String storeName,
    required String tenderImageUrl,
  }) {
    return CartItem(
      product: Product(
        id: -DateTime.now().millisecondsSinceEpoch,
        name: 'مناقصة: $category',
        description: '',
        price: price.toStringAsFixed(2),
        images: <String>[tenderImageUrl],
        categoryIds: const <int>[],
      ),
      quantity: 1,
      storeId: storeId,
      storeName: storeName,
      imageUrl: tenderImageUrl,
      isTender: true,
      tenderId: tenderId,
      tenderImageUrl: tenderImageUrl,
    );
  }

  /// يُستخدم عند بناء السطر من [Product] أو بعد التحديث من Firestore.
  static String defaultImageUrlForProduct(Product p) => p.images.isNotEmpty ? p.images.first : '';

  double get totalPrice {
    final p = (selectedVariant?.price ?? product.price).trim();
    if (p.contains('–')) {
      final first = p.split('–').first.trim();
      return (double.tryParse(first) ?? 0) * quantity;
    }
    return (double.tryParse(p) ?? 0) * quantity;
  }

  Map<String, dynamic> toJson() => {
        'quantity': quantity,
        if (backendLineId != null && backendLineId!.isNotEmpty) 'backendLineId': backendLineId,
        'storeId': storeId,
        'storeName': storeName,
        'imageUrl': imageUrl,
        'isTender': isTender,
        if (tenderId != null) 'tenderId': tenderId,
        if (tenderImageUrl != null) 'tenderImageUrl': tenderImageUrl,
        'isWholesale': isWholesale,
        if (minQuantity != null) 'minQuantity': minQuantity,
        if (selectedVariant != null) 'selectedVariant': selectedVariant!.toJson(),
        'product': {
          'id': product.id,
          'name': product.name,
          'description': product.description,
          'price': product.price,
          'images': product.images.map((e) => {'src': e}).toList(),
          'categories': product.categoryIds.map((e) => {'id': e}).toList(),
          'tags': product.tagIds.map((e) => {'id': e}).toList(),
          if (product.categoryField != null) 'categoryField': product.categoryField,
          if (product.subCategoryField != null) 'subCategoryField': product.subCategoryField,
          if (product.createdAtFirestore != null)
            'createdAtFirestore': product.createdAtFirestore!.toIso8601String(),
          'stock': product.stock,
          'stockStatus': product.stockStatus,
          'hasVariants': product.hasVariants,
          'variants': product.variants.map((e) => e.toJson()).toList(),
          'isBoosted': product.isBoosted,
          'isTrending': product.isTrending,
        },
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final product = Product.fromJson(json['product'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final imageUrlRaw = json['imageUrl'] as String?;
    return CartItem(
      quantity: json['quantity'] as int? ?? 1,
      backendLineId: json['backendLineId'] as String?,
      product: product,
      storeId: json['storeId'] as String? ?? 'ammarjo',
      storeName: json['storeName'] as String? ?? 'متجر عمار جو',
      imageUrl: (imageUrlRaw != null && imageUrlRaw.isNotEmpty) ? imageUrlRaw : defaultImageUrlForProduct(product),
      isTender: json['isTender'] as bool? ?? false,
      tenderId: json['tenderId'] as String?,
      tenderImageUrl: json['tenderImageUrl'] as String?,
      isWholesale: json['isWholesale'] as bool? ?? false,
      minQuantity: json['minQuantity'] as int?,
      selectedVariant: json['selectedVariant'] is Map<String, dynamic>
          ? ProductVariant.fromJson(json['selectedVariant'] as Map<String, dynamic>)
          : (json['selectedVariant'] is Map
                ? ProductVariant.fromJson(Map<String, dynamic>.from(json['selectedVariant'] as Map))
                : null),
    );
  }

  /// NestJS `GET /cart` → [CartItem] (minimal [Product] for pricing/checkout).
  factory CartItem.fromBackendCartRow(Map<String, dynamic> json) {
    final pid = json['productId'] is int
        ? json['productId'] as int
        : int.tryParse(json['productId']?.toString() ?? '') ?? 0;
    final price = json['priceSnapshot']?.toString() ?? '0';
    final name = json['productName']?.toString() ?? '';
    final img = json['imageUrl']?.toString() ?? '';
    final sid = json['storeId']?.toString() ?? 'ammarjo';
    final sname = json['storeName']?.toString() ?? 'متجر';
    final vid = json['variantId']?.toString();
    ProductVariant? sv;
    if (vid != null && vid.isNotEmpty) {
      sv = ProductVariant(id: vid, price: price, stock: -1, options: const <ProductVariantOption>[]);
    }
    return CartItem(
      backendLineId: json['id']?.toString(),
      product: Product(
        id: pid,
        name: name.isNotEmpty ? name : 'Product',
        description: '',
        price: price,
        images: img.isNotEmpty ? <String>[img] : <String>[],
        categoryIds: const <int>[],
        hasVariants: sv != null,
        variants: sv != null ? <ProductVariant>[sv] : const <ProductVariant>[],
      ),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      storeId: sid,
      storeName: sname,
      imageUrl: img,
      selectedVariant: sv,
    );
  }
}

class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.price,
    required this.stock,
    required this.options,
    this.isDefault = false,
  });

  final String id;
  final String price;
  final int stock;
  final bool isDefault;
  final List<ProductVariantOption> options;

  bool get isAvailable => stock > 0;

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id']?.toString() ?? '',
      price: (json['price'] ?? '0').toString(),
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      isDefault: json['isDefault'] == true || json['is_default'] == true,
      options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((x) => ProductVariantOption.fromJson(Map<String, dynamic>.from(x)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'price': price,
        'stock': stock,
        'isDefault': isDefault,
        'options': options.map((e) => e.toJson()).toList(),
      };
}

class ProductVariantOption {
  const ProductVariantOption({
    required this.optionType,
    required this.optionValue,
  });

  final String optionType;
  final String optionValue;

  factory ProductVariantOption.fromJson(Map<String, dynamic> json) {
    return ProductVariantOption(
      optionType: json['optionType']?.toString() ?? json['option_type']?.toString() ?? '',
      optionValue: json['optionValue']?.toString() ?? json['option_value']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'optionType': optionType,
        'optionValue': optionValue,
      };
}

class CustomerProfile {
  final String email;
  final String? token;
  final String? fullName;
  /// Local loyalty balance (١ دينار ≈ ١ نقطة عند إتمام الطلب).
  final int loyaltyPoints;

  /// حقول إضافية للتوصيل والعرض (تُحفظ محلياً وفي Firestore).
  final String? firstName;
  final String? lastName;
  final String? phoneLocal;
  final String? addressLine;
  final String? city;
  final String? country;

  /// بريد تواصل حقيقي (اختياري)؛ [email] يبقى البريد التركيبي للهاتف عند الحاجة.
  final String? contactEmail;

  const CustomerProfile({
    required this.email,
    this.token,
    this.fullName,
    this.loyaltyPoints = 0,
    this.firstName,
    this.lastName,
    this.phoneLocal,
    this.addressLine,
    this.city,
    this.country,
    this.contactEmail,
  });

  /// الاسم المعروض: الاسم الكامل أو الاسم الأول + العائلة.
  String get displayName {
    final f = fullName?.trim();
    if (f != null && f.isNotEmpty) return f;
    final a = firstName?.trim() ?? '';
    final b = lastName?.trim() ?? '';
    final c = '$a $b'.trim();
    return c.isNotEmpty ? c : 'عميل';
  }

  CustomerProfile copyWith({
    String? email,
    String? token,
    String? fullName,
    int? loyaltyPoints,
    String? firstName,
    String? lastName,
    String? phoneLocal,
    String? addressLine,
    String? city,
    String? country,
    String? contactEmail,
  }) {
    return CustomerProfile(
      email: email ?? this.email,
      token: token ?? this.token,
      fullName: fullName ?? this.fullName,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneLocal: phoneLocal ?? this.phoneLocal,
      addressLine: addressLine ?? this.addressLine,
      city: city ?? this.city,
      country: country ?? this.country,
      contactEmail: contactEmail ?? this.contactEmail,
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        if (token != null) 'token': token,
        if (fullName != null) 'fullName': fullName,
        'loyaltyPoints': loyaltyPoints,
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (phoneLocal != null) 'phoneLocal': phoneLocal,
        if (addressLine != null) 'addressLine': addressLine,
        if (city != null) 'city': city,
        if (country != null) 'country': country,
        if (contactEmail != null) 'contactEmail': contactEmail,
      };

  factory CustomerProfile.fromJson(Map<String, dynamic> j) {
    return CustomerProfile(
      email: j['email']?.toString() ?? '',
      token: j['token']?.toString(),
      fullName: j['fullName']?.toString(),
      loyaltyPoints: (j['loyaltyPoints'] as num?)?.toInt() ?? 0,
      firstName: j['firstName']?.toString(),
      lastName: j['lastName']?.toString(),
      phoneLocal: j['phoneLocal']?.toString(),
      addressLine: j['addressLine']?.toString(),
      city: j['city']?.toString(),
      country: j['country']?.toString(),
      contactEmail: j['contactEmail']?.toString(),
    );
  }
}
