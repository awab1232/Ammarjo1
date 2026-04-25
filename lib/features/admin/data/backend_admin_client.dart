import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/services/firebase_auth_header_provider.dart';

/// نتيجة [BackendAdminClient.patchAdminStoreCommissionPercent] — يُستدعى مسارًا تجريبيًا قد لا يكون مفعّلاً في الخادم.
enum AdminStoreCommissionPercentPatchResult { saved, notSupported, failed }

/// Authenticated REST client for NestJS `/admin/rest/*` (Bearer = Firebase ID token).
final class BackendAdminClient {
  BackendAdminClient._();
  static final BackendAdminClient instance = BackendAdminClient._();

  Future<String?> _idToken() async {
    try {
      return await FirebaseAuthHeaderProvider.requireIdToken(reason: 'backend_admin_id_token');
    } on Object {
      debugPrint('[BackendAdminClient] getIdToken failed');
      return null;
    }
  }

  String _base() {
    final b = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    return b;
  }

  Future<Map<String, dynamic>?> _get(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) return null;
    final base = _base();
    if (base.isEmpty) return null;
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    try {
      final res = await http
          .get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BackendAdminClient] GET $path → ${res.statusCode}');
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) {
        debugPrint('[BackendAdminClient] GET $path responseJson runtimeType: ${decoded.runtimeType}');
        return <String, dynamic>{'items': decoded};
      }
      return null;
    } on Object {
      debugPrint('[BackendAdminClient] GET $path failed');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _patch(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) return null;
    final base = _base();
    if (base.isEmpty) return null;
    final uri = Uri.parse('$base$path');
    try {
      final res = await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BackendAdminClient] PATCH $path → ${res.statusCode} ${res.body}');
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{'ok': true};
    } on Object {
      debugPrint('[BackendAdminClient] PATCH $path failed');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _delete(String path, {Duration timeout = const Duration(seconds: 25)}) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) return null;
    final base = _base();
    if (base.isEmpty) return null;
    final uri = Uri.parse('$base$path');
    try {
      final res = await http.delete(uri, headers: {'Authorization': 'Bearer $token'}).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BackendAdminClient] DELETE $path → ${res.statusCode}');
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{'ok': true};
    } on Object {
      debugPrint('[BackendAdminClient] DELETE $path failed');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) return null;
    final base = _base();
    if (base.isEmpty) return null;
    final uri = Uri.parse('$base$path');
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BackendAdminClient] POST $path → ${res.statusCode} ${res.body}');
        return null;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{'ok': true};
    } on Object {
      debugPrint('[BackendAdminClient] POST $path failed');
      return null;
    }
  }

  // ——— Users ———

  Future<Map<String, dynamic>?> fetchUsers({int limit = 50, int offset = 0}) {
    return _get('/admin/rest/users', query: {'limit': '$limit', 'offset': '$offset'});
  }

  Future<Map<String, dynamic>?> getUserById(String id) {
    return _get('/admin/rest/users/${Uri.encodeComponent(id.trim())}');
  }

  Future<Map<String, dynamic>?> updateUser(
    String id, {
    String? role,
    bool? banned,
    String? bannedReason,
    double? walletBalance,
  }) {
    final body = <String, dynamic>{
      if (role != null) 'role': role,
      if (banned != null) 'banned': banned,
      if (bannedReason != null) 'bannedReason': bannedReason,
      if (walletBalance != null) 'walletBalance': walletBalance,
    };
    if (body.isEmpty) {
      return Future.value(<String, dynamic>{'ok': true});
    }
    return _patch('/admin/rest/users/${Uri.encodeComponent(id.trim())}', body: body);
  }

  Future<Map<String, dynamic>?> deleteUser(String id) {
    return _delete('/admin/rest/users/${Uri.encodeComponent(id.trim())}');
  }

  // ——— Stores ———

  Future<Map<String, dynamic>?> fetchStores({int limit = 50, int offset = 0}) {
    return _get('/admin/rest/stores', query: {'limit': '$limit', 'offset': '$offset'});
  }

  Future<Map<String, dynamic>?> updateStoreStatus(String id, String status) {
    return _patch(
      '/admin/rest/stores/${Uri.encodeComponent(id.trim())}/status',
      body: {'status': status},
    );
  }

  Future<Map<String, dynamic>?> updateStoreFeatures(
    String id, {
    bool? isFeatured,
    bool? isBoosted,
    String? boostExpiresAt,
  }) {
    return _patch(
      '/admin/rest/stores/${Uri.encodeComponent(id.trim())}/features',
      body: {
        if (isFeatured != null) 'isFeatured': isFeatured,
        if (isBoosted != null) 'isBoosted': isBoosted,
        if (boostExpiresAt != null) 'boostExpiresAt': boostExpiresAt,
      },
    );
  }

  Future<Map<String, dynamic>?> fetchBoostRequests({String status = 'all'}) {
    return _get('/admin/rest/boost-requests', query: {'status': status});
  }

  Future<Map<String, dynamic>?> patchBoostRequestStatus(
    String id, {
    required String status,
  }) {
    return _patch('/admin/rest/boost-requests/${Uri.encodeComponent(id.trim())}', body: {'status': status});
  }

  // ——— Technicians ———

  Future<Map<String, dynamic>?> fetchTechnicians() => _get('/admin/rest/technicians');

  Future<Map<String, dynamic>?> updateTechnicianStatus(String id, String status) {
    return _patch(
      '/admin/rest/technicians/${Uri.encodeComponent(id.trim())}/status',
      body: {'status': status},
    );
  }

  Future<Map<String, dynamic>?> updateTechnicianProfile(
    String id, {
    String? displayName,
    String? email,
    String? phone,
    String? city,
    String? category,
    List<String>? specialties,
    List<String>? cities,
    String? status,
  }) {
    final body = <String, dynamic>{
      if (displayName != null) 'displayName': displayName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (city != null) 'city': city,
      if (category != null) 'category': category,
      if (specialties != null) 'specialties': specialties,
      if (cities != null) 'cities': cities,
      if (status != null) 'status': status,
    };
    return _patch(
      '/admin/rest/technicians/${Uri.encodeComponent(id.trim())}/profile',
      body: body,
    );
  }

  Future<Map<String, dynamic>?> fetchTechnicianJoinRequests() =>
      _get('/admin/rest/technician-join-requests');

  Future<Map<String, dynamic>?> patchTechnicianJoinRequest(
    String id, {
    required String status,
    String? rejectionReason,
    String? reviewedBy,
  }) {
    return _patch(
      '/admin/rest/technician-join-requests/${Uri.encodeComponent(id.trim())}',
      body: {
        'status': status,
        if (rejectionReason != null) 'rejectionReason': rejectionReason,
        if (reviewedBy != null) 'reviewedBy': reviewedBy,
      },
    );
  }

  // ——— Reports ———

  Future<Map<String, dynamic>?> fetchReports() => _get('/admin/rest/reports');

  Future<Map<String, dynamic>?> patchReport(
    String id, {
    String? status,
    String? subject,
    String? bodyText,
  }) {
    return _patch(
      '/admin/rest/reports/${Uri.encodeComponent(id.trim())}',
      body: {
        if (status != null) 'status': status,
        if (subject != null) 'subject': subject,
        if (bodyText != null) 'bodyText': bodyText,
      },
    );
  }

  // ——— System ———

  Future<Map<String, dynamic>?> fetchSystemLogs({int limit = 100}) {
    return _get('/admin/rest/system/logs', query: {'limit': '$limit'});
  }

  Future<Map<String, dynamic>?> fetchAuditLogs({int limit = 50, int offset = 0}) {
    return _get('/admin/rest/audit-logs', query: {'limit': '$limit', 'offset': '$offset'});
  }

  // ——— Analytics ———

  Future<Map<String, dynamic>?> fetchOverview() => _get('/admin/rest/analytics/overview');

  Future<Map<String, dynamic>?> fetchFinance() => _get('/admin/rest/analytics/finance');

  Future<Map<String, dynamic>?> fetchActivity() => _get('/admin/rest/analytics/activity');

  // ——— Orders (admin list) ———

  Future<Map<String, dynamic>?> fetchOrders({
    int limit = 50,
    int offset = 0,
    String? deliveryStatus,
    String? driverId,
    String? dateFrom,
    String? dateTo,
    String? search,
  }) {
    return _get(
      '/admin/rest/orders',
      query: {
        'limit': '$limit',
        'offset': '$offset',
        if (deliveryStatus != null && deliveryStatus.trim().isNotEmpty) 'deliveryStatus': deliveryStatus.trim(),
        if (driverId != null && driverId.trim().isNotEmpty) 'driverId': driverId.trim(),
        if (dateFrom != null && dateFrom.trim().isNotEmpty) 'dateFrom': dateFrom.trim(),
        if (dateTo != null && dateTo.trim().isNotEmpty) 'dateTo': dateTo.trim(),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
  }

  /// سائقون متاحون (إحداثيات + متصلون) — GET `/drivers/available`.
  Future<Map<String, dynamic>?> fetchAvailableDrivers() => _get('/drivers/available');

  /// إعادة تعيين تلقائية — POST `/admin/rest/orders/:id/retry-assignment`.
  Future<Map<String, dynamic>?> postAdminRetryDeliveryAssignment(String orderId) {
    return _post(
      '/admin/rest/orders/${Uri.encodeComponent(orderId.trim())}/retry-assignment',
      body: const <String, dynamic>{},
    );
  }

  /// PATCH `/orders/:id/assign-driver` — تعيين يدوي لسائق.
  Future<Map<String, dynamic>?> patchAssignDriverToOrder(
    String orderId,
    String driverId, {
    double? deliveryLat,
    double? deliveryLng,
  }) {
    return _patch(
      '/orders/${Uri.encodeComponent(orderId.trim())}/assign-driver',
      body: <String, dynamic>{
        'driverId': driverId.trim(),
        if (deliveryLat != null) 'deliveryLat': deliveryLat,
        if (deliveryLng != null) 'deliveryLng': deliveryLng,
      },
    );
  }

  Future<Map<String, dynamic>?> patchOrderStatus(String orderId, String status) {
    return _patch(
      '/orders/${Uri.encodeComponent(orderId.trim())}/status',
      body: {'status': status},
    );
  }

  // ——— Migration hub status (JSON blob) ———

  Future<Map<String, dynamic>?> fetchMigrationStatus() => _get('/admin/rest/migration-status');

  Future<Map<String, dynamic>?> patchMigrationStatus(Map<String, dynamic> payload) {
    return _patch('/admin/rest/migration-status', body: {'payload': payload});
  }

  // ——— Generic authed GET for store commissions (reuses same API host + token) ———

  Future<Map<String, dynamic>?> fetchStoreCommissionsSnapshot(String storeId) {
    return _get('/stores/${Uri.encodeComponent(storeId.trim())}/commissions');
  }

  /// POST `/stores/:storeId/commissions/pay` — تسجيل دفعة عمولة (يتطلب صلاحية كتابة).
  Future<Map<String, dynamic>?> postStoreCommissionPayment(String storeId, double amount) {
    return _post(
      '/stores/${Uri.encodeComponent(storeId.trim())}/commissions/pay',
      body: {'amount': amount},
    );
  }

  /// Wholesale list (existing `/wholesale/*` routes).
  Future<Map<String, dynamic>?> fetchWholesaleStores({int limit = 50, String? cursor}) {
    return _get('/wholesale/stores', query: {
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    });
  }

  Future<Map<String, dynamic>?> fetchWholesaleOrders({
    String? storeId,
    String? wholesalerId,
    int limit = 30,
    String? cursor,
  }) {
    return _get('/wholesale/orders', query: {
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (storeId != null && storeId.isNotEmpty) 'storeId': storeId,
      if (wholesalerId != null && wholesalerId.isNotEmpty) 'wholesalerId': wholesalerId,
    });
  }

  Future<Map<String, dynamic>?> fetchServiceRequests({
    String? customerId,
    String? technicianId,
    String? status,
    int limit = 20,
    String? cursor,
  }) {
    return _get('/service-requests', query: {
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (customerId != null && customerId.isNotEmpty) 'customerId': customerId,
      if (technicianId != null && technicianId.isNotEmpty) 'technicianId': technicianId,
      if (status != null && status.isNotEmpty) 'status': status,
    });
  }

  // ——— Coupons ———

  Future<Map<String, dynamic>?> fetchCoupons({int limit = 50, int offset = 0}) {
    return _get('/admin/rest/coupons', query: {'limit': '$limit', 'offset': '$offset'});
  }

  Future<Map<String, dynamic>?> createCoupon({
    required String code,
    String? name,
    String? status,
    Map<String, dynamic>? payload,
  }) {
    return _post('/admin/rest/coupons', body: {
      'code': code,
      if (name != null) 'name': name,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>?> updateCoupon(
    String id, {
    String? code,
    String? name,
    String? status,
    Map<String, dynamic>? payload,
  }) {
    return _patch('/admin/rest/coupons/${Uri.encodeComponent(id.trim())}', body: {
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>?> deleteCoupon(String id) {
    return _delete('/admin/rest/coupons/${Uri.encodeComponent(id.trim())}');
  }

  // ——— Promotions ———

  Future<Map<String, dynamic>?> fetchPromotions({int limit = 50, int offset = 0}) {
    return _get('/admin/rest/promotions', query: {'limit': '$limit', 'offset': '$offset'});
  }

  Future<Map<String, dynamic>?> createPromotion({
    required String name,
    String? promoType,
    String? status,
    Map<String, dynamic>? payload,
  }) {
    return _post('/admin/rest/promotions', body: {
      'name': name,
      if (promoType != null) 'promoType': promoType,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>?> updatePromotion(
    String id, {
    String? name,
    String? promoType,
    String? status,
    Map<String, dynamic>? payload,
  }) {
    return _patch('/admin/rest/promotions/${Uri.encodeComponent(id.trim())}', body: {
      if (name != null) 'name': name,
      if (promoType != null) 'promoType': promoType,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>?> deletePromotion(String id) {
    return _delete('/admin/rest/promotions/${Uri.encodeComponent(id.trim())}');
  }

  // ——— Tenders ———

  Future<Map<String, dynamic>?> fetchTenders() => _get('/admin/rest/tenders');

  Future<Map<String, dynamic>?> updateTender(
    String id, {
    String? status,
    String? title,
    Map<String, dynamic>? payload,
  }) {
    return _patch('/admin/rest/tenders/${Uri.encodeComponent(id.trim())}', body: {
      if (status != null) 'status': status,
      if (title != null) 'title': title,
      if (payload != null) 'payload': payload,
    });
  }

  // ——— Support tickets ———

  Future<Map<String, dynamic>?> fetchSupportTickets() => _get('/admin/rest/support/tickets');

  Future<Map<String, dynamic>?> updateSupportTicket(
    String id, {
    String? status,
    String? subject,
    Map<String, dynamic>? payload,
  }) {
    return _patch('/admin/rest/support/tickets/${Uri.encodeComponent(id.trim())}', body: {
      if (status != null) 'status': status,
      if (subject != null) 'subject': subject,
      if (payload != null) 'payload': payload,
    });
  }

  // ——— Wholesalers ———

  Future<Map<String, dynamic>?> fetchWholesalers() => _get('/admin/rest/wholesalers');

  Future<Map<String, dynamic>?> updateWholesaler(
    String id, {
    String? status,
    String? name,
    String? category,
    String? city,
    double? commission,
  }) {
    return _patch('/admin/rest/wholesalers/${Uri.encodeComponent(id.trim())}', body: {
      if (status != null) 'status': status,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (city != null) 'city': city,
      if (commission != null) 'commission': commission,
    });
  }

  // ——— Categories ———

  Future<Map<String, dynamic>?> fetchCategories({String kind = 'all'}) {
    return _get('/admin/rest/categories', query: {'kind': kind});
  }

  Future<Map<String, dynamic>?> createCategory({
    required String name,
    String? kind,
    String? status,
    Map<String, dynamic>? payload,
  }) {
    return _post('/admin/rest/categories', body: {
      'name': name,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>?> updateCategory(
    String id, {
    String? name,
    String? kind,
    String? status,
    Map<String, dynamic>? payload,
  }) {
    return _patch('/admin/rest/categories/${Uri.encodeComponent(id.trim())}', body: {
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>?> patchCategoryCommission(
    String id, {
    required double commissionPercent,
  }) {
    return _patch(
      '/admin/rest/categories/${Uri.encodeComponent(id.trim())}/commission',
      body: {'commissionPercent': commissionPercent},
    );
  }

  Future<Map<String, dynamic>?> deleteCategory(String id) {
    return _delete('/admin/rest/categories/${Uri.encodeComponent(id.trim())}');
  }

  Future<Map<String, dynamic>?> broadcastNotification({
    required String title,
    required String body,
    String? targetRole,
    Map<String, dynamic>? data,
  }) {
    return _post('/admin/rest/notifications/broadcast', body: {
      'title': title,
      'body': body,
      if (targetRole != null && targetRole.trim().isNotEmpty) 'targetRole': targetRole.trim(),
      if (data != null) 'data': data,
    });
  }

  // ——— Settings ———

  Future<Map<String, dynamic>?> fetchSettings() => _get('/admin/rest/settings');

  Future<Map<String, dynamic>?> updateSettings(Map<String, dynamic> payload) {
    return _patch('/admin/rest/settings', body: {'payload': payload});
  }

  // ——— Home sections / sub-categories ———

  Future<Map<String, dynamic>?> fetchSubCategories({required String sectionId}) {
    return _get('/admin/rest/sub-categories', query: {'sectionId': sectionId.trim()});
  }

  Future<Map<String, dynamic>?> createSubCategory({
    required String homeSectionId,
    required String name,
    String? image,
    int sortOrder = 0,
    bool isActive = true,
  }) {
    return _post('/admin/rest/sub-categories', body: {
      'homeSectionId': homeSectionId.trim(),
      'name': name.trim(),
      if (image != null) 'image': image,
      'sortOrder': sortOrder,
      'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> updateSubCategory(
    String id, {
    String? homeSectionId,
    String? name,
    String? image,
    int? sortOrder,
    bool? isActive,
  }) {
    return _patch('/admin/rest/sub-categories/${Uri.encodeComponent(id.trim())}', body: {
      if (homeSectionId != null) 'homeSectionId': homeSectionId.trim(),
      if (name != null) 'name': name.trim(),
      if (image != null) 'image': image,
      if (sortOrder != null) 'sortOrder': sortOrder,
      if (isActive != null) 'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> deleteSubCategory(String id) {
    return _delete('/admin/rest/sub-categories/${Uri.encodeComponent(id.trim())}');
  }

  Future<Map<String, dynamic>?> fetchHomeSections() {
    return _get('/admin/rest/home-sections');
  }

  Future<Map<String, dynamic>?> fetchHomeCms() {
    return _get('/admin/rest/home-cms');
  }

  Future<Map<String, dynamic>?> patchHomeCms(Map<String, dynamic> body) {
    return _patch('/admin/rest/home-cms', body: body);
  }

  Future<Map<String, dynamic>?> fetchBanners() {
    return _get('/banners', query: {'all': 'true'});
  }

  Future<Map<String, dynamic>?> createBanner({
    required String imageUrl,
    required String title,
    String? link,
    int order = 0,
    bool isActive = true,
  }) {
    return _post('/banners', body: {
      'imageUrl': imageUrl,
      'title': title,
      if (link != null) 'link': link,
      'order': order,
      'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> updateBanner(
    String id, {
    String? imageUrl,
    String? title,
    String? link,
    int? order,
    bool? isActive,
  }) {
    return _patch('/banners/${Uri.encodeComponent(id.trim())}', body: {
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (title != null) 'title': title,
      if (link != null) 'link': link,
      if (order != null) 'order': order,
      if (isActive != null) 'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> deleteBanner(String id) {
    return _delete('/banners/${Uri.encodeComponent(id.trim())}');
  }

  Future<Map<String, dynamic>?> fetchStoreTypes() {
    return _get('/admin/rest/store-types');
  }

  Future<Map<String, dynamic>?> createStoreType({
    required String name,
    required String key,
    String? icon,
    String? image,
    int displayOrder = 0,
    bool isActive = true,
  }) {
    return _post('/admin/rest/store-types', body: {
      'name': name.trim(),
      'key': key.trim(),
      if (icon != null) 'icon': icon,
      if (image != null) 'image': image,
      'displayOrder': displayOrder,
      'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> updateStoreType(
    String id, {
    String? name,
    String? key,
    String? icon,
    String? image,
    int? displayOrder,
    bool? isActive,
  }) {
    return _patch('/admin/rest/store-types/${Uri.encodeComponent(id.trim())}', body: {
      if (name != null) 'name': name.trim(),
      if (key != null) 'key': key.trim(),
      if (icon != null) 'icon': icon,
      if (image != null) 'image': image,
      if (displayOrder != null) 'displayOrder': displayOrder,
      if (isActive != null) 'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> deleteStoreType(String id) {
    return _delete('/admin/rest/store-types/${Uri.encodeComponent(id.trim())}');
  }

  Future<Map<String, dynamic>?> createHomeSection({
    required String name,
    required String type,
    String? storeTypeId,
    String? image,
    bool isActive = true,
  }) {
    return _post('/admin/rest/home-sections', body: {
      'name': name.trim(),
      'type': type.trim(),
      if (storeTypeId != null) 'storeTypeId': storeTypeId.trim(),
      if (image != null) 'image': image,
      'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> updateHomeSection(
    String id, {
    String? name,
    String? type,
    String? storeTypeId,
    String? image,
    bool? isActive,
  }) {
    return _patch('/admin/rest/home-sections/${Uri.encodeComponent(id.trim())}', body: {
      if (name != null) 'name': name.trim(),
      if (type != null) 'type': type.trim(),
      if (storeTypeId != null) 'storeTypeId': storeTypeId.trim(),
      if (image != null) 'image': image,
      if (isActive != null) 'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> deleteHomeSection(String id) {
    return _delete('/admin/rest/home-sections/${Uri.encodeComponent(id.trim())}');
  }

  // ——— Marketplace products (new filter + admin CRUD) ———

  Future<Map<String, dynamic>?> fetchFilteredProducts({
    String? subCategoryId,
    String? storeId,
    String? sectionId,
    String? search,
    double? minPrice,
    double? maxPrice,
    int limit = 100,
    int offset = 0,
  }) {
    return _get('/products/filter', query: {
      if (subCategoryId != null && subCategoryId.trim().isNotEmpty) 'subCategoryId': subCategoryId.trim(),
      if (storeId != null && storeId.trim().isNotEmpty) 'storeId': storeId.trim(),
      if (sectionId != null && sectionId.trim().isNotEmpty) 'sectionId': sectionId.trim(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (minPrice != null) 'minPrice': '$minPrice',
      if (maxPrice != null) 'maxPrice': '$maxPrice',
      'limit': '$limit',
      'offset': '$offset',
    });
  }

  Future<Map<String, dynamic>?> createMarketplaceProduct({
    required String storeId,
    String? subCategoryId,
    required String name,
    String? description,
    double? price,
    String? image,
    int? stock,
    bool isActive = true,
  }) {
    return _post('/products', body: {
      'storeId': storeId.trim(),
      if (subCategoryId != null && subCategoryId.trim().isNotEmpty) 'subCategoryId': subCategoryId.trim(),
      'name': name.trim(),
      if (description != null) 'description': description.trim(),
      'price': price ?? 0,
      if (image != null) 'image': image,
      'stock': stock ?? 0,
      'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> updateMarketplaceProduct(
    String id, {
    String? storeId,
    String? subCategoryId,
    String? name,
    String? description,
    double? price,
    String? image,
    int? stock,
    bool? isActive,
  }) {
    return _patch('/products/${Uri.encodeComponent(id.trim())}', body: {
      if (storeId != null) 'storeId': storeId.trim(),
      if (subCategoryId != null) 'subCategoryId': subCategoryId.trim(),
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
      if (price != null) 'price': price,
      if (image != null) 'image': image,
      if (stock != null) 'stock': stock,
      if (isActive != null) 'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>?> deleteMarketplaceProduct(String id) {
    return _delete('/products/${Uri.encodeComponent(id.trim())}');
  }

  Future<Map<String, dynamic>?> bulkUpdateMarketplaceStock(List<Map<String, dynamic>> items) {
    return _patch('/products/bulk-stock', body: {'items': items});
  }

  Future<Map<String, dynamic>?> updateProductBoost(
    String id, {
    bool? isBoosted,
    bool? isTrending,
  }) {
    return _patch('/admin/rest/products/${Uri.encodeComponent(id.trim())}/boost', body: {
      if (isBoosted != null) 'isBoosted': isBoosted,
      if (isTrending != null) 'isTrending': isTrending,
    });
  }

  /// `PATCH /admin/rest/stores/:id/commission` مع `{ "commissionPercent": … }` (0–100).
  Future<AdminStoreCommissionPercentPatchResult> patchAdminStoreCommissionPercent(
    String storeId,
    double percent,
  ) async {
    final id = storeId.trim();
    if (id.isEmpty) return AdminStoreCommissionPercentPatchResult.failed;
    try {
      final token = await _idToken();
      final base = _base();
      if (base.isEmpty) return AdminStoreCommissionPercentPatchResult.failed;
      final uri = Uri.parse('$base/admin/rest/stores/${Uri.encodeComponent(id)}/commission');
      final res = await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'commissionPercent': percent}),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 404 || res.statusCode == 405) {
        return AdminStoreCommissionPercentPatchResult.notSupported;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BackendAdminClient] patchAdminStoreCommissionPercent → ${res.statusCode} ${res.body}');
        return AdminStoreCommissionPercentPatchResult.failed;
      }
      return AdminStoreCommissionPercentPatchResult.saved;
    } on Object catch (e) {
      debugPrint('[BackendAdminClient] patchAdminStoreCommissionPercent error: $e');
      return AdminStoreCommissionPercentPatchResult.failed;
    }
  }

  // ——— Driver onboarding (admin) ———

  Future<Map<String, dynamic>?> fetchDriverRequests() => _get('/admin/rest/driver-requests');

  Future<Map<String, dynamic>?> approveDriverRequest(String id) => _post(
        '/admin/rest/driver-requests/${Uri.encodeComponent(id.trim())}/approve',
        body: const <String, dynamic>{},
      );

  Future<Map<String, dynamic>?> rejectDriverRequest(String id) => _post(
        '/admin/rest/driver-requests/${Uri.encodeComponent(id.trim())}/reject',
        body: const <String, dynamic>{},
      );
}
