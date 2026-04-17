// LEGACY - WooCommerce migration
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../core/config/woo_jwt_holder.dart';
import '../../../core/network/json_utf8.dart';
import '../domain/models.dart';
import '../domain/store_currency.dart';

const String _wooStoreUrl = 'https://ammarjo.net';
const String _wooApiBase = '$_wooStoreUrl/wp-json/wc/v3';
const String _wooConsumerKey = String.fromEnvironment('WOO_CONSUMER_KEY');
const String _wooConsumerSecret = String.fromEnvironment('WOO_CONSUMER_SECRET');
const String _wooJwtLoginEndpoint = '$_wooStoreUrl/wp-json/jwt-auth/v1/token';

class WooApiException implements Exception {
  final String message;
  WooApiException(this.message);
  @override
  String toString() => message;
}

/// تخزين مؤقت لطلبات GET إلى Woo REST (دقيقتان) لتسريع إعادة فتح الصفحات.
class _WooHttpCache {
  _WooHttpCache._();
  static final Map<String, _CacheEntry> _map = <String, _CacheEntry>{};
  static const Duration ttl = Duration(minutes: 2);

  static String? get(String key) {
    final e = _map[key];
    if (e == null) return null;
    if (DateTime.now().isAfter(e.expires)) {
      _map.remove(key);
      return null;
    }
    return e.body;
  }

  static void put(String key, String body) {
    _map[key] = _CacheEntry(body, DateTime.now().add(ttl));
  }

  static void clear() => _map.clear();
}

class _CacheEntry {
  _CacheEntry(this.body, this.expires);
  final String body;
  final DateTime expires;
}

/// نتيجة إنشاء طلب عبر Woo REST — تُستخدم لمزامنة `users/{uid}/orders` في Firestore.
class WooOrderCreateResult {
  WooOrderCreateResult({
    required this.id,
    required this.status,
    required this.total,
    required this.listTitle,
    this.dateCreated,
  });

  final int id;
  final String status;
  final String total;
  /// عنوان قصير لقائمة «طلباتي» (أول بند + عدد إضافي أو رقم الطلب).
  final String listTitle;
  final DateTime? dateCreated;

  factory WooOrderCreateResult.fromWooOrderJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int
        ? rawId
        : rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? (throw StateError('NULL_RESPONSE'))) ??
                (throw StateError('INVALID_NUMERIC_DATA'));
    final createdRaw = json['date_created']?.toString();
    DateTime? created;
    if (createdRaw != null && createdRaw.isNotEmpty) {
      created = DateTime.tryParse(createdRaw);
    }
    return WooOrderCreateResult(
      id: id,
      status: json['status']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      total: json['total']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      listTitle: _listTitleFromOrderJson(json),
      dateCreated: created,
    );
  }

  static String _listTitleFromOrderJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final idStr = rawId?.toString() ?? (throw StateError('NULL_RESPONSE'));
    final items = json['line_items'] as List<dynamic>? ?? <dynamic>[];
    if (items.isNotEmpty) {
      final first = items.first;
      if (first is Map<String, dynamic>) {
        var name = first['name']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
        if (name.isNotEmpty) {
          if (items.length > 1) {
            name = '$name (+${items.length - 1})';
          }
          if (name.length > 60) {
            name = '${name.substring(0, 57)}…';
          }
          return name;
        }
      }
    }
    return idStr.isNotEmpty ? 'طلب #$idStr' : 'طلب';
  }
}

typedef ProductList = List<Product>;
typedef ProductCategoryList = List<ProductCategory>;
typedef JsonMapList = List<Map<String, dynamic>>;

class WooApiService {
  /// يُزامن مع [WooJwtHolder] — استدعِه بعد تحميل الجلسة أو تسجيل الدخول/الخروج.
  void setJwtToken(String? token) {
    WooJwtHolder.setToken(token);
  }

  /// يُستدعى بعد تعديلات الأدمن على Woo (منتجات/أقسام/طلبات) لإبطال التخزين المؤقت.
  void clearGetCache() => _WooHttpCache.clear();

  Map<String, String> _headersForWoo({bool jsonBody = false}) {
    final h = <String, String>{...WooJwtHolder.authorizationHeaders()};
    if (jsonBody) {
      h['Content-Type'] = 'application/json; charset=utf-8';
    }
    return h;
  }

  /// [jwtUserContext]: عند `true` ووجود JWT في [WooJwtHolder] يُحمَّل الطلب بـ **Bearer فقط**
  /// (بدون `consumer_key`/`consumer_secret` في الـ query) — يُنصح لـ POST الطلبات والعملاء
  /// بعد تسجيل الدخول لتجنّب تعارض المصادقة على الخادم.
  Uri _wcUri(String endpoint, [Map<String, String>? query, bool jwtUserContext = false]) {
    final hasJwt = WooJwtHolder.token != null && WooJwtHolder.token!.trim().isNotEmpty;
    final bearerOnly = hasJwt && jwtUserContext;
    final q = <String, String>{
      if (!bearerOnly) 'consumer_key': _wooConsumerKey,
      if (!bearerOnly) 'consumer_secret': _wooConsumerSecret,
      ...?query,
    };
    return Uri.parse('$_wooApiBase/$endpoint').replace(queryParameters: q);
  }

  String _wooErrorMessageFromResponse(http.Response response, String fallback) {
    try {
      final decoded = jsonDecodeUtf8Response(response);
      if (decoded is Map<String, dynamic>) {
        final m = decoded['message'] ?? decoded['code'];
        if (m != null && m.toString().isNotEmpty) {
          return '$fallback (${response.statusCode}): $m';
        }
      }
    } on Object {
      developer.log('Woo error response parse failed', name: 'WooApiService');
    }
    final code = response.statusCode;
    return '$fallback (HTTP $code)';
  }

  /// [categoryId] maps to WooCommerce `category` query param (filters by category).
  ///
  /// [orderby]: `date`, `popularity`, `rating`, `price`, … — راجع وثائق Woo REST.
  Future<ProductList> fetchProducts({
    int page = 1,
    int perPage = 20,
    int? categoryId,
    /// معرف وسم منتج WooCommerce (`tag` في REST).
    int? tagId,
    String? orderby,
    String? order,
    String? search,
    bool featured = false,
  }) async {
    final q = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
    };
    if (categoryId != null) {
      q['category'] = '$categoryId';
    }
    if (tagId != null) {
      q['tag'] = '$tagId';
    }
    if (featured) {
      q['featured'] = 'true';
    }
    if (orderby != null && orderby.isNotEmpty) {
      q['orderby'] = orderby;
    }
    if (order != null && order.isNotEmpty) {
      q['order'] = order;
    }
    if (search != null && search.trim().isNotEmpty) {
      q['search'] = search.trim();
    }
    final uri = _wcUri('products', q);
    final cacheKey = uri.toString();
    final cached = _WooHttpCache.get(cacheKey);
    final dynamic decoded = cached != null
        ? jsonDecode(cached)
        : null;
    if (decoded == null) {
      final response = await http.get(uri, headers: _headersForWoo());
      if (response.statusCode != 200) {
        throw WooApiException('تعذر تحميل المنتجات. (${response.statusCode})');
      }
      _WooHttpCache.put(cacheKey, response.body);
      final d2 = jsonDecodeUtf8Response(response);
      return _parseProductListJson(d2);
    }
    return _parseProductListJson(decoded);
  }

  List<Product> _parseProductListJson(dynamic decoded) {
    if (decoded is! List<dynamic>) {
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message']?.toString() ??
            decoded['code']?.toString() ??
            (throw StateError('NULL_RESPONSE'));
        throw WooApiException(msg.isEmpty ? 'استجابة غير صالحة من الخادم' : msg);
      }
      throw WooApiException('تعذر قراءة قائمة المنتجات.');
    }
    final out = <Product>[];
    for (final e in decoded) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(Product.fromJson(e));
        } on Object {
          /* تخطَ المنتجات التالفة */
        }
      }
    }
    return out;
  }

  /// منتجات مُعلّمة «مميزة» في WooCommerce — مثالية لبانر الصفحة الرئيسية.
  Future<ProductList> fetchFeaturedProducts({int perPage = 5}) async {
    return fetchProducts(
      perPage: perPage,
      orderby: 'date',
      order: 'desc',
      featured: true,
    );
  }

  /// منتج واحد بالمعرّف — لمزامنة السلة مع بيانات الخادم (اسم، سعر، صور).
  Future<Product?> fetchProductById(int id) async {
    final response = await http.get(_wcUri('products/$id'), headers: _headersForWoo());
    if (response.statusCode != 200) {
      throw StateError('NULL_RESPONSE');
    }
    try {
      final decoded = jsonDecodeUtf8Response(response);
      if (decoded is! Map<String, dynamic>) throw StateError('NULL_RESPONSE');
      return Product.fromJson(decoded);
    } on Object {
      throw StateError('NULL_RESPONSE');
    }
  }

  /// Store currency + decimal places from **WooCommerce → الإعدادات → عام**.
  Future<StoreCurrency> fetchStoreCurrency() async {
    final uri = _wcUri('settings/general');
    final key = uri.toString();
    final cached = _WooHttpCache.get(key);
    final List<dynamic> list;
    if (cached != null) {
      final decoded = jsonDecode(cached);
      if (decoded is! List<dynamic>) {
        return StoreCurrency.fromWooSettings(currencyCode: 'JOD', priceNumDecimals: 3);
      }
      list = decoded;
    } else {
      final response = await http.get(uri, headers: _headersForWoo());
      if (response.statusCode != 200) {
        return StoreCurrency.fromWooSettings(currencyCode: 'JOD', priceNumDecimals: 3);
      }
      _WooHttpCache.put(key, response.body);
      list = jsonDecodeUtf8Response(response) as List<dynamic>;
    }
    String? currencyCode;
    int? decimals;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final id = map['id']?.toString();
      if (id == 'woocommerce_currency') {
        currencyCode = map['value']?.toString();
      } else if (id == 'woocommerce_price_num_decimals') {
        decimals = int.tryParse(map['value']?.toString() ?? '');
      }
    }
    return StoreCurrency.fromWooSettings(
      currencyCode: currencyCode,
      priceNumDecimals: decimals,
    );
  }

  List<ProductCategory> _parseCategoryList(dynamic decoded) {
    if (decoded is! List<dynamic>) {
      return <ProductCategory>[];
    }
    final out = <ProductCategory>[];
    for (final e in decoded) {
      if (e is Map<String, dynamic>) {
        try {
          out.add(ProductCategory.fromJson(e));
        } on Object {
          developer.log('Woo category parse skipped invalid row', name: 'WooApiService');
        }
      }
    }
    return out;
  }

  Future<ProductCategoryList> fetchCategories() async {
    final uri = _wcUri('products/categories', {'per_page': '100'});
    final key = uri.toString();
    final cached = _WooHttpCache.get(key);
    if (cached != null) {
      return _parseCategoryList(jsonDecode(cached));
    }
    final response = await http.get(uri, headers: _headersForWoo());
    if (response.statusCode != 200) {
      throw WooApiException('تعذر تحميل الأقسام. (${response.statusCode})');
    }
    _WooHttpCache.put(key, response.body);
    return _parseCategoryList(jsonDecodeUtf8Response(response));
  }

  /// Child categories (`parent` = WooCommerce category id).
  Future<ProductCategoryList> fetchChildCategories(int parentId) async {
    final uri = _wcUri('products/categories', {
      'per_page': '100',
      'parent': '$parentId',
    });
    final key = uri.toString();
    final cached = _WooHttpCache.get(key);
    if (cached != null) {
      return _parseCategoryList(jsonDecode(cached));
    }
    final response = await http.get(uri, headers: _headersForWoo());
    if (response.statusCode != 200) {
      throw WooApiException('تعذر تحميل الأقسام الفرعية. (${response.statusCode})');
    }
    _WooHttpCache.put(key, response.body);
    return _parseCategoryList(jsonDecodeUtf8Response(response));
  }

  Future<CustomerProfile> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse(_wooJwtLoginEndpoint),
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode != 200) {
      if (response.statusCode == 404) {
        throw WooApiException(
          'خدمة تسجيل الدخول (JWT) غير متاحة على الموقع. ثبّت إضافة JWT Authentication أو راجع المسار.',
        );
      }
      throw WooApiException('فشل تسجيل الدخول. تحقق من بياناتك.');
    }
    final body = jsonDecodeUtf8Response(response) as Map<String, dynamic>;
    return CustomerProfile(
      email: body['user_email']?.toString() ?? (throw StateError('NULL_RESPONSE')),
      token: body['token']?.toString(),
      fullName: body['user_display_name']?.toString(),
    );
  }

  Future<void> register({
    required String email,
    required String firstName,
    required String lastName,
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      _wcUri('customers', null, true),
      headers: _headersForWoo(jsonBody: true),
      body: jsonEncode({
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'password': password,
      }),
    );
    if (response.statusCode != 201) {
      throw WooApiException(
        _wooErrorMessageFromResponse(response, 'تعذر إنشاء الحساب'),
      );
    }
  }

  Future<WooOrderCreateResult> createOrder({
    required List<CartItem> items,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String address1,
    required String city,
    required String country,
  }) async {
    final lineItems = items
        .map((item) => {'product_id': item.product.id, 'quantity': item.quantity})
        .toList();
    final body = {
      'payment_method': 'cod',
      'payment_method_title': 'الدفع عند الاستلام',
      'set_paid': false,
      'billing': {
        'first_name': firstName,
        'last_name': lastName,
        'address_1': address1,
        'city': city,
        'country': country,
        'email': email,
        'phone': phone,
      },
      'shipping': {
        'first_name': firstName,
        'last_name': lastName,
        'address_1': address1,
        'city': city,
        'country': country,
      },
      'line_items': lineItems,
    };
    final response = await http.post(
      _wcUri('orders', null, true),
      headers: _headersForWoo(jsonBody: true),
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      throw WooApiException(
        _wooErrorMessageFromResponse(response, 'فشل إرسال الطلب'),
      );
    }
    final decoded = jsonDecodeUtf8Response(response);
    if (decoded is! Map<String, dynamic>) {
      throw WooApiException('استجابة غير صالحة من المتجر بعد إنشاء الطلب.');
    }
    return WooOrderCreateResult.fromWooOrderJson(decoded);
  }

  // --- Admin (Woo REST + مفاتيح المتجر — ليس JWT فقط) ---

  Future<JsonMapList> fetchOrdersAdmin({
    int page = 1,
    int perPage = 50,
    String? status,
  }) async {
    final q = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'orderby': 'date',
      'order': 'desc',
    };
    if (status != null && status.isNotEmpty && status != 'any') {
      q['status'] = status;
    }
    final uri = _wcUri('orders', q, false);
    final response = await http.get(uri, headers: _headersForWoo());
    if (response.statusCode != 200) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر تحميل الطلبات'));
    }
    final decoded = jsonDecodeUtf8Response(response);
    if (decoded is! List<dynamic>) {
      throw WooApiException('استجابة طلبات غير صالحة');
    }
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> updateOrderStatusAdmin(int orderId, String status) async {
    final uri = _wcUri('orders/$orderId', null, false);
    final response = await http.put(
      uri,
      headers: _headersForWoo(jsonBody: true),
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر تحديث حالة الطلب'));
    }
    clearGetCache();
  }

  Future<ProductCategory> createProductCategoryAdmin({
    required String name,
    int parent = 0,
  }) async {
    final uri = _wcUri('products/categories', null, false);
    final response = await http.post(
      uri,
      headers: _headersForWoo(jsonBody: true),
      body: jsonEncode({
        'name': name,
        'parent': parent,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر إنشاء القسم'));
    }
    clearGetCache();
    final decoded = jsonDecodeUtf8Response(response);
    if (decoded is! Map<String, dynamic>) {
      throw WooApiException('استجابة غير صالحة');
    }
    return ProductCategory.fromJson(decoded);
  }

  Future<ProductCategory> updateProductCategoryAdmin(
    int id, {
    String? name,
    int? parent,
  }) async {
    final uri = _wcUri('products/categories/$id', null, false);
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (parent != null) body['parent'] = parent;
    final response = await http.put(
      uri,
      headers: _headersForWoo(jsonBody: true),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر تحديث القسم'));
    }
    clearGetCache();
    final decoded = jsonDecodeUtf8Response(response);
    if (decoded is! Map<String, dynamic>) {
      throw WooApiException('استجابة غير صالحة');
    }
    return ProductCategory.fromJson(decoded);
  }

  Future<void> deleteProductCategoryAdmin(int id) async {
    final uri = _wcUri('products/categories/$id', {'force': 'true'}, false);
    final response = await http.delete(uri, headers: _headersForWoo());
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر حذف القسم'));
    }
    clearGetCache();
  }

  Future<Product> createProductAdmin({
    required String name,
    required String regularPrice,
    required String description,
    String shortDescription = '',
    required List<int> categoryIds,
    required List<String> imageUrls,
    bool manageStock = true,
    int? stockQuantity,
    String stockStatus = 'instock',
  }) async {
    final uri = _wcUri('products', null, false);
    final images = imageUrls.map((src) => {'src': src}).toList();
    final categories = categoryIds.map((id) => {'id': id}).toList();
    final body = <String, dynamic>{
      'name': name,
      'type': 'simple',
      'regular_price': regularPrice,
      'description': description,
      'short_description': shortDescription,
      'categories': categories,
      'images': images,
      'manage_stock': manageStock,
      'stock_status': stockStatus,
    };
    if (manageStock && stockQuantity != null) {
      body['stock_quantity'] = stockQuantity;
    }
    final response = await http.post(
      uri,
      headers: _headersForWoo(jsonBody: true),
      body: jsonEncode(body),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر إنشاء المنتج'));
    }
    clearGetCache();
    final decoded = jsonDecodeUtf8Response(response);
    if (decoded is! Map<String, dynamic>) {
      throw WooApiException('استجابة غير صالحة');
    }
    return Product.fromJson(decoded);
  }

  Future<Product> updateProductAdmin(
    int id, {
    String? name,
    String? regularPrice,
    String? description,
    String? shortDescription,
    List<int>? categoryIds,
    List<String>? imageUrls,
    bool? manageStock,
    int? stockQuantity,
    String? stockStatus,
  }) async {
    final uri = _wcUri('products/$id', null, false);
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (regularPrice != null) body['regular_price'] = regularPrice;
    if (description != null) body['description'] = description;
    if (shortDescription != null) body['short_description'] = shortDescription;
    if (categoryIds != null) {
      body['categories'] = categoryIds.map((e) => {'id': e}).toList();
    }
    if (imageUrls != null) {
      body['images'] = imageUrls.map((src) => {'src': src}).toList();
    }
    if (manageStock != null) body['manage_stock'] = manageStock;
    if (stockQuantity != null) body['stock_quantity'] = stockQuantity;
    if (stockStatus != null) body['stock_status'] = stockStatus;
    final response = await http.put(
      uri,
      headers: _headersForWoo(jsonBody: true),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر تحديث المنتج'));
    }
    clearGetCache();
    final decoded = jsonDecodeUtf8Response(response);
    if (decoded is! Map<String, dynamic>) {
      throw WooApiException('استجابة غير صالحة');
    }
    return Product.fromJson(decoded);
  }

  Future<void> deleteProductAdmin(int id) async {
    final uri = _wcUri('products/$id', {'force': 'true'}, false);
    final response = await http.delete(uri, headers: _headersForWoo());
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر حذف المنتج'));
    }
    clearGetCache();
  }

  /// كتالوج إداري (بدون فلتر تخزين مؤقت قديم).
  Future<ProductList> fetchProductsAdmin({int page = 1, int perPage = 100}) async {
    final uri = _wcUri('products', {
      'page': '$page',
      'per_page': '$perPage',
      'orderby': 'date',
      'order': 'desc',
    }, false);
    final response = await http.get(uri, headers: _headersForWoo());
    if (response.statusCode != 200) {
      throw WooApiException(_wooErrorMessageFromResponse(response, 'تعذر تحميل المنتجات'));
    }
    return _parseProductListJson(jsonDecodeUtf8Response(response));
  }

  static const int _migrationPageSize = 10;
  static const Duration _migrationDelayBetweenPages = Duration(seconds: 1);

  static String _migrationHttpHint(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'Unauthorized — تحقق من مفاتيح Woo REST أو الصلاحيات';
      case 403:
        return 'Forbidden — صلاحيات المفتاح، أو حظر من الخادم، أو CORS على الويب';
      case 404:
        return 'Not Found — مسار REST غير صحيح';
      case 429:
        return 'Too Many Requests — أبطئ الطلبات أو انتظر';
      default:
        return 'HTTP $statusCode';
    }
  }

  /// طلب GET للهجرة مع تسجيل تفصيلي (رمز الحالة + جسم الاستجابة) عند الفشل.
  Future<http.Response> _migrationGetLogged(Uri uri, String label) async {
    try {
      final response = await http.get(uri, headers: _headersForWoo());
      if (response.statusCode != 200) {
        final previewLen = response.body.length > 800 ? 800 : response.body.length;
        final preview = previewLen == 0 ? '(empty body)' : response.body.substring(0, previewLen);
        final hint = _migrationHttpHint(response.statusCode);
        developer.log(
          'WooMigration[$label] FAILED status=${response.statusCode} ($hint)\n'
          'URI: $uri\n'
          'Body (first $previewLen chars):\n$preview',
          name: 'WooMigration',
        );
        final msg = _wooErrorMessageFromResponse(response, 'تعذر تحميل البيانات');
        throw WooApiException(
          '$label: HTTP ${response.statusCode} — $hint. $msg',
        );
      }
      return response;
    } on WooApiException {
      rethrow;
    } on Object {
      developer.log(
        'WooMigration[$label] network/client error',
        name: 'WooMigration',
      );
      throw WooApiException('$label: network error');
    }
  }

  /// Migration Hub: جميع أقسام المنتجات — صفحات صغيرة + تأخير بين الصفحات (تخفيف ضغط السيرفر / CORS).
  Future<JsonMapList> fetchAllProductCategoriesRawForMigration() async {
    const perPage = _migrationPageSize;
    final all = <Map<String, dynamic>>[];
    for (var page = 1;; page++) {
      if (page > 1) {
        await Future<void>.delayed(_migrationDelayBetweenPages);
      }
      final uri = _wcUri('products/categories', {
        'per_page': '$perPage',
        'page': '$page',
      }, false);
      final response = await _migrationGetLogged(uri, 'categories page $page');
      final decoded = jsonDecodeUtf8Response(response);
      if (decoded is! List<dynamic>) break;
      if (decoded.isEmpty) break;
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          all.add(Map<String, dynamic>.from(e));
        }
      }
      if (decoded.length < perPage) break;
    }
    return all;
  }

  /// Migration Hub: جميع المنتجات — صفحات صغيرة + تأخير بين الصفحات.
  Future<JsonMapList> fetchAllProductsRawForMigration() async {
    const perPage = _migrationPageSize;
    final all = <Map<String, dynamic>>[];
    for (var page = 1;; page++) {
      if (page > 1) {
        await Future<void>.delayed(_migrationDelayBetweenPages);
      }
      final uri = _wcUri('products', {
        'per_page': '$perPage',
        'page': '$page',
        'status': 'any',
        'orderby': 'id',
        'order': 'asc',
      }, false);
      final response = await _migrationGetLogged(uri, 'products page $page');
      final decoded = jsonDecodeUtf8Response(response);
      if (decoded is! List<dynamic>) break;
      if (decoded.isEmpty) break;
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          all.add(Map<String, dynamic>.from(e));
        }
      }
      if (decoded.length < perPage) break;
    }
    return all;
  }
}
