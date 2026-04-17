import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/backend_orders_config.dart';
import '../contracts/feature_state.dart';
import '../logging/backend_fallback_logger.dart';
import '../models/backend_auth_me.dart';
import '../models/home_section.dart';
import '../models/sub_category.dart';
import '../models/marketplace_product.dart';
import '../../features/stores/domain/store_model.dart';
import '../monitoring/sentry_safe.dart';
import '../contracts/feature_state.dart';
import '../contracts/feature_unit.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef VersionedJsonList = ({JsonList items, int version});

/// HTTP client for the shadow orders API (Bearer = Firebase ID token).
final class BackendOrdersClient {
  BackendOrdersClient._();
  static final BackendOrdersClient instance = BackendOrdersClient._();

  Map<String, dynamic>? _safeMap(Map<String, dynamic>? source) {
    if (source == null) throw StateError('NULL_RESPONSE');
    final out = <String, dynamic>{};
    for (final entry in source.entries) {
      final k = entry.key.toLowerCase();
      if (k.contains('token') || k.contains('password') || k.contains('authorization') || k.contains('secret')) {
        out[entry.key] = '[REDACTED]';
      } else {
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  Future<void> _captureApiFailure({
    required Object error,
    required String endpoint,
    int? statusCode,
    Map<String, dynamic>? requestBody,
    String? responseBody,
  }) {
    return sentryCaptureExceptionSafe(
      error,
      stackTrace: StackTrace.current,
      withScope: (scope) {
        scope.level = SentryLevel.error;
        scope.setTag('client', 'backend_orders_client');
        scope.setTag('endpoint', endpoint);
        if (statusCode != null) {
          scope.setContexts('http', {'statusCode': statusCode});
        }
        if (requestBody != null) scope.setContexts('request', _safeMap(requestBody) ?? {});
        if (responseBody != null && responseBody.isNotEmpty) {
          final clean = responseBody.length > 1000 ? responseBody.substring(0, 1000) : responseBody;
          scope.setContexts('response', {'body': clean});
        }
      },
    );
  }

  /// Primary write: POST `/orders`, returns server [id] or `null` (no throw). Used when [BackendOrdersConfig.useBackendOrdersWrite].
  Future<String?> createOrderPrimary(Map<String, dynamic> payload) async {
    if (!BackendOrdersConfig.useBackendOrdersWrite) throw StateError('NULL_RESPONSE');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('orders_write_primary');
      throw StateError('NULL_RESPONSE');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('NULL_RESPONSE');
    final String? token = await _idToken(user);
    if (token == null || token.isEmpty) throw StateError('NULL_RESPONSE');

    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/orders');
    final Duration t = BackendOrdersConfig.backendOrdersWriteTimeout;
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(t);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('BackendOrders: primary POST /orders failed ${res.statusCode} ${res.body}');
        }
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'orders_write_primary',
          reason: 'http_${res.statusCode}',
          extra: {'path': '/orders'},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'POST /orders',
          statusCode: res.statusCode,
          requestBody: payload,
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) throw StateError('NULL_RESPONSE');
      final m = Map<String, dynamic>.from(decoded);
      final id = m['id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
      final order = m['order'];
      if (order is Map) {
        final om = Map<String, dynamic>.from(order);
        final oid = om['orderId']?.toString().trim();
        if (oid != null && oid.isNotEmpty) return oid;
      }
      throw StateError('NULL_RESPONSE');
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('BackendOrders: primary POST /orders timed out after ${t.inSeconds}s');
      }
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'orders_write_primary',
        reason: 'timeout',
        extra: {'timeoutSeconds': t.inSeconds},
      );
      await _captureApiFailure(
        error: TimeoutException('POST /orders timed out'),
        endpoint: 'POST /orders',
        requestBody: payload,
      );
      throw StateError('NULL_RESPONSE');
    } on Object {
      if (kDebugMode) {
        debugPrint('BackendOrders: primary POST /orders error');
      }
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'orders_write_primary',
        reason: 'unknown_error',
      );
      await _captureApiFailure(
        error: StateError('POST /orders failed'),
        endpoint: 'POST /orders',
        requestBody: payload,
      );
      throw StateError('NULL_RESPONSE');
    }
  }

  /// Fire-and-forget: logs failures only; never throws to callers.
  Future<void> recordOrderCreated(Map<String, dynamic> payload) async {
    if (!BackendOrdersConfig.useBackendOrders) return;
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('orders_shadow_post');
      debugPrint('BackendOrders: BACKEND_ORDERS_BASE_URL empty, skip shadow POST');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('BackendOrders: no signed-in user, skip shadow POST');
      return;
    }
    final String? token = await _idToken(user);
    if (token == null || token.isEmpty) return;

    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/orders');
    try {
      final res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          'BackendOrders: POST /orders failed ${res.statusCode} ${res.body}',
        );
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'orders_shadow_post',
          reason: 'http_${res.statusCode}',
          extra: {'path': '/orders'},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'POST /orders (shadow)',
          statusCode: res.statusCode,
          requestBody: payload,
          responseBody: res.body,
        );
      }
    } on Object {
      debugPrint('BackendOrders: POST /orders error');
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'orders_shadow_post',
        reason: 'unknown_error',
      );
      await _captureApiFailure(
        error: StateError('POST /orders shadow failed'),
        endpoint: 'POST /orders (shadow)',
        requestBody: payload,
      );
    }
  }

  /// GET `/orders/:id` with [timeout]. Returns `null` on skip, HTTP error, timeout, or invalid JSON.
  Future<Map<String, dynamic>?> fetchOrderGet(
    String orderId, {
    Duration? timeout,
  }) async {
    if (!BackendOrdersConfig.useBackendOrdersRead) throw StateError('NULL_RESPONSE');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('orders_read_get');
      throw StateError('NULL_RESPONSE');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('NULL_RESPONSE');
    final String? token = await _idToken(user);
    if (token == null || token.isEmpty) throw StateError('NULL_RESPONSE');

    final uri = Uri.parse(
      '${base.replaceAll(RegExp(r'/$'), '')}/orders/${Uri.encodeComponent(orderId)}',
    );
    final Duration t = timeout ?? BackendOrdersConfig.backendOrdersReadTimeout;
    try {
      final res = await http
          .get(
            uri,
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(t);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('BackendOrders: GET /orders/$orderId failed ${res.statusCode}');
        }
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'orders_read_get',
          reason: 'http_${res.statusCode}',
          extra: {'orderId': orderId},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'GET /orders/:id',
          statusCode: res.statusCode,
          requestBody: {'orderId': orderId},
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw StateError('NULL_RESPONSE');
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('BackendOrders: GET /orders/$orderId timed out after ${t.inMilliseconds}ms');
      }
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'orders_read_get',
        reason: 'timeout',
        extra: {'orderId': orderId, 'timeoutMs': t.inMilliseconds},
      );
      await _captureApiFailure(
        error: TimeoutException('GET /orders/:id timed out'),
        endpoint: 'GET /orders/:id',
        requestBody: {'orderId': orderId},
      );
      throw StateError('NULL_RESPONSE');
    } on Object {
      if (kDebugMode) {
        debugPrint('BackendOrders: GET /orders/$orderId error');
      }
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'orders_read_get',
        reason: 'unknown_error',
        extra: {'orderId': orderId},
      );
      await _captureApiFailure(
        error: StateError('GET /orders/:id failed'),
        endpoint: 'GET /orders/:id',
        requestBody: {'orderId': orderId},
      );
      throw StateError('NULL_RESPONSE');
    }
  }

  Future<JsonList?> fetchOrdersForCurrentUser({
    int limit = 20,
    String? cursor,
  }) async {
    if (!BackendOrdersConfig.useBackendOrdersRead) throw StateError('NULL_RESPONSE');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('NULL_RESPONSE');
    final uid = user.uid.trim();
    if (uid.isEmpty) throw StateError('NULL_RESPONSE');
    final body = await _authedGetJson(
      '/users/${Uri.encodeComponent(uid)}/orders',
      query: {
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
      flow: 'orders_read_list',
    );
    final items = body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String?> _idToken(User user) async {
    try {
      return await user.getIdToken();
    } on Object {
      debugPrint('BackendOrders: getIdToken failed');
      throw StateError('NULL_RESPONSE');
    }
  }

  Future<Map<String, dynamic>?> _authedPostJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 20),
    required String flow,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('NULL_RESPONSE');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('NULL_RESPONSE');
    final token = await _idToken(user);
    if (token == null || token.isEmpty) throw StateError('NULL_RESPONSE');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
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
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: flow,
          reason: 'http_${res.statusCode}',
          extra: {'path': path},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'POST $path',
          statusCode: res.statusCode,
          requestBody: body,
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(error: StateError('POST $path failed'), endpoint: 'POST $path', requestBody: body);
      throw StateError('NULL_RESPONSE');
    }
  }

  Future<Map<String, dynamic>?> _authedPatchJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 20),
    required String flow,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('NULL_RESPONSE');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('NULL_RESPONSE');
    final token = await _idToken(user);
    if (token == null || token.isEmpty) throw StateError('NULL_RESPONSE');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
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
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: flow,
          reason: 'http_${res.statusCode}',
          extra: {'path': path},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'PATCH $path',
          statusCode: res.statusCode,
          requestBody: body,
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(error: StateError('PATCH $path failed'), endpoint: 'PATCH $path', requestBody: body);
      throw StateError('NULL_RESPONSE');
    }
  }

  Future<bool> _authedDelete(
    String path, {
    Duration timeout = const Duration(seconds: 20),
    required String flow,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      return false;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final token = await _idToken(user);
    if (token == null || token.isEmpty) return false;
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    try {
      final res = await http.delete(uri, headers: {'Authorization': 'Bearer $token'}).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: flow,
          reason: 'http_${res.statusCode}',
          extra: {'path': path},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'DELETE $path',
          statusCode: res.statusCode,
          responseBody: res.body,
        );
        return false;
      }
      return true;
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(error: StateError('DELETE $path failed'), endpoint: 'DELETE $path');
      return false;
    }
  }

  Future<Map<String, dynamic>?> _authedGetJson(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
    required String flow,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('NULL_RESPONSE');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('NULL_RESPONSE');
    final token = await _idToken(user);
    if (token == null || token.isEmpty) throw StateError('NULL_RESPONSE');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    try {
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: flow,
          reason: 'http_${res.statusCode}',
          extra: {'path': path},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'GET $path',
          statusCode: res.statusCode,
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw StateError('NULL_RESPONSE');
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(
        error: StateError('GET $path failed'),
        endpoint: 'GET $path',
      );
      throw StateError('NULL_RESPONSE');
    }
  }

  Future<Map<String, dynamic>?> _publicGetJson(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
    required String flow,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('NULL_RESPONSE');
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    try {
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: flow,
          reason: 'http_${res.statusCode}',
          extra: {'path': path},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'GET $path',
          statusCode: res.statusCode,
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw StateError('NULL_RESPONSE');
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(
        error: StateError('GET $path failed'),
        endpoint: 'GET $path',
      );
      throw StateError('NULL_RESPONSE');
    }
  }

  Future<JsonList?> fetchStores({
    String? category,
    int limit = 100,
    String? cursor,
  }) async {
    final body = await _authedGetJson(
      '/stores',
      query: {
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
      flow: 'stores_list',
    );
    final items = body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    final out = <Map<String, dynamic>>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (category != null && category.trim().isNotEmpty) {
        if ((row['category']?.toString() ?? '').trim() != category.trim()) continue;
      }
      out.add(row);
    }
    return out;
  }

  Future<JsonList?> fetchStoreTypes() async {
    final data = await fetchStoreTypesVersioned();
    return data?.items;
  }

  Future<VersionedJsonList?> fetchStoreTypesVersioned() async {
    final body = await _publicGetJson('/stores/store-types', flow: 'stores_types_public');
    final items = body?['data'] ?? body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    final list = items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final version = (body?['version'] as num?)?.toInt() ?? 1;
    return (items: list, version: version);
  }

  Future<JsonList?> fetchPendingStores({int limit = 200, int offset = 0}) async {
    final body = await _authedGetJson(
      '/admin/rest/stores',
      query: {'limit': '$limit', 'offset': '$offset'},
      flow: 'admin_stores_pending_list',
    );
    final items = body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    final all = items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return all.where((row) {
      final s = (row['status']?.toString() ?? '').trim().toLowerCase();
      return s == 'pending' || s == 'under_review';
    }).toList();
  }

  Future<Map<String, dynamic>?> patchStoreStatus({
    required String storeId,
    required String status,
  }) {
    return _authedPatchJson(
      '/admin/rest/stores/${Uri.encodeComponent(storeId.trim())}/status',
      body: <String, dynamic>{'status': status.trim()},
      flow: 'admin_store_status_patch',
    );
  }

  Future<bool> deleteStoreById(String storeId) {
    return _authedDelete(
      '/stores/${Uri.encodeComponent(storeId.trim())}',
      flow: 'admin_store_delete',
    );
  }

  Future<Map<String, dynamic>?> fetchStoreById(String storeId) {
    return _authedGetJson('/stores/${Uri.encodeComponent(storeId.trim())}', flow: 'store_by_id');
  }

  Future<JsonList?> fetchStoreCategories(String storeId) async {
    final body = await _authedGetJson('/stores/${Uri.encodeComponent(storeId.trim())}/categories', flow: 'store_categories');
    if (body == null) throw StateError('NULL_RESPONSE');
    if (body['items'] is List) {
      return (body['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw StateError('NULL_RESPONSE');
  }

  Future<JsonList?> fetchProductsByStore({
    required String storeId,
    int limit = 100,
    String? cursor,
  }) async {
    final body = await _authedGetJson(
      '/products',
      query: {
        'storeId': storeId.trim(),
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
      flow: 'products_by_store',
    );
    final items = body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> upsertAdminProduct({
    String? productId,
    required Map<String, dynamic> payload,
  }) {
    final id = productId?.trim() ?? '';
    if (id.isEmpty) {
      return _authedPostJson(
        '/products',
        body: payload,
        flow: 'admin_product_create',
      );
    }
    return _authedPatchJson(
      '/products/${Uri.encodeComponent(id)}',
      body: payload,
      flow: 'admin_product_patch',
    );
  }

  Future<bool> deleteAdminProductById(String productId) {
    return _authedDelete(
      '/products/${Uri.encodeComponent(productId.trim())}',
      flow: 'admin_product_delete',
    );
  }

  Future<JsonList?> fetchPublicProducts({int limit = 400}) async {
    final body = await _authedGetJson(
      '/products',
      query: {'limit': '$limit'},
      flow: 'products_public_list',
    );
    final items = body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<JsonList?> fetchBanners() async {
    final body = await _publicGetJson('/banners', flow: 'public_banners');
    final items = body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> postChatMessageSent({
    required String conversationId,
    required String senderId,
    required String targetUserId,
    String type = 'general',
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await _idToken(user);
    if (token == null || token.isEmpty) return;
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/internal/chat-events/message-sent');
    final payload = <String, dynamic>{
      'conversationId': conversationId,
      'senderId': senderId,
      'targetUserId': targetUserId,
      'type': type,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          if (const String.fromEnvironment('INTERNAL_API_KEY').trim().isNotEmpty)
            'x-internal-api-key': const String.fromEnvironment('INTERNAL_API_KEY').trim(),
        },
        body: jsonEncode(payload),
      );
    } on Object {
      debugPrint('BackendOrders: message-sent event post failed');
    }
  }

  Future<JsonList?> searchProducts({
    required String query,
    int hitsPerPage = 20,
    int page = 0,
    String? storeId,
    String? category,
    double? minPrice,
    double? maxPrice,
  }) async {
    final body = await _publicGetJson(
      '/search/products',
      query: {
        'q': query.trim(),
        'hitsPerPage': '$hitsPerPage',
        'page': '$page',
        if (storeId != null && storeId.trim().isNotEmpty) 'storeId': storeId.trim(),
        if (category != null && category.trim().isNotEmpty) 'category': category.trim(),
        if (minPrice != null) 'minPrice': '$minPrice',
        if (maxPrice != null) 'maxPrice': '$maxPrice',
      },
      flow: 'search_products',
    );
    if (body == null) throw StateError('NULL_RESPONSE');
    final hits = body['hits'];
    if (hits is! List) throw StateError('NULL_RESPONSE');
    return hits.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Submit a store opening request (no Firestore). Backend stores/logs the payload.
  Future<bool> submitStoreApplication(Map<String, dynamic> payload) async {
    final res = await _authedPostJson(
      '/store-requests',
      body: payload,
      flow: 'store_request_submit',
    );
    return res != null;
  }

  /// Registers or refreshes the current device session on the backend.
  Future<void> postAuthSession({
    required String deviceId,
    required String deviceName,
    required String deviceOs,
    required String appVersion,
  }) async {
    await _authedPostJson(
      '/auth/session',
      body: {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceOs': deviceOs,
        'appVersion': appVersion,
      },
      flow: 'auth_session_register',
    );
  }

  /// Lists active sessions for the signed-in user.
  ///
  /// Returns an explicit [FeatureState] instead of raw rows so the UI can
  /// surface missing-backend / auth-failure / transport-error conditions
  /// without silent empty lists (see zero-violation contract).
  Future<FeatureState<List<Map<String, dynamic>>>> fetchMySessions() async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('fetch_my_sessions');
      return FeatureState.missingBackend('auth_sessions');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return FeatureState.failure('not_authenticated');
    }
    final token = await _idToken(user);
    if (token == null || token.isEmpty) {
      return FeatureState.failure('token_unavailable');
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/auth/sessions');
    try {
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        return FeatureState.failure('HTTP ${res.statusCode}');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final sessions = body['sessions'];
      final list = <Map<String, dynamic>>[];
      if (sessions is List) {
        for (final e in sessions) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      return FeatureState.success(list);
    } on Object catch (e) {
      return FeatureState.failure('fetch_my_sessions_failed', e);
    }
  }

  Future<JsonList?> searchStores({
    required String query,
    int hitsPerPage = 20,
    int page = 0,
    String? city,
    String? category,
  }) async {
    final body = await _publicGetJson(
      '/search/stores',
      query: {
        'q': query.trim(),
        'hitsPerPage': '$hitsPerPage',
        'page': '$page',
        if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        if (category != null && category.trim().isNotEmpty) 'category': category.trim(),
      },
      flow: 'search_stores',
    );
    if (body == null) throw StateError('NULL_RESPONSE');
    final hits = body['hits'];
    if (hits is! List) throw StateError('NULL_RESPONSE');
    return hits.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Object?> _internalGetJson(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
    required String flow,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('NULL_RESPONSE');
    }
    final internalApiKey = const String.fromEnvironment('INTERNAL_API_KEY', defaultValue: '').trim();
    if (internalApiKey.isEmpty) {
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: flow,
        reason: 'missing_internal_api_key',
      );
      throw StateError('NULL_RESPONSE');
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    try {
      final res = await http.get(uri, headers: {'x-internal-api-key': internalApiKey}).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: flow,
          reason: 'http_${res.statusCode}',
          extra: {'path': path},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'GET $path',
          statusCode: res.statusCode,
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      return jsonDecode(res.body);
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(
        error: StateError('GET $path failed'),
        endpoint: 'GET $path',
      );
      throw StateError('NULL_RESPONSE');
    }
  }

  Future<Map<String, dynamic>?> fetchAnalyticsOverview() async {
    final body = await _internalGetJson('/internal/analytics/summary', flow: 'analytics_overview');
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    throw StateError('NULL_RESPONSE');
  }

  Future<JsonList?> fetchAnalyticsDaily({int days = 30}) async {
    final body = await _internalGetJson(
      '/internal/analytics/timeline',
      query: {'days': '$days'},
      flow: 'analytics_daily',
    );
    if (body is! List) throw StateError('NULL_RESPONSE');
    return body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<JsonList?> fetchAnalyticsStores({int limit = 10}) async {
    final body = await _internalGetJson(
      '/internal/analytics/top-technicians',
      query: {'limit': '$limit'},
      flow: 'analytics_stores',
    );
    if (body is! List) throw StateError('NULL_RESPONSE');
    return body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<JsonList?> fetchAnalyticsRevenue({int limit = 50}) async {
    final body = await _internalGetJson(
      '/internal/analytics/slow-requests',
      query: {'limit': '$limit'},
      flow: 'analytics_revenue',
    );
    if (body is! List) throw StateError('NULL_RESPONSE');
    return body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<JsonList?> fetchCart() async {
    if (!BackendOrdersConfig.useBackendCart) throw StateError('NULL_RESPONSE');
    final body = await _authedGetJson('/cart', flow: 'cart_list');
    final items = body?['items'];
    if (items is! List) throw StateError('NULL_RESPONSE');
    return items
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          final id = m['id']?.toString();
          return <String, dynamic>{
            'id': id,
            'productId': m['productId'],
            'variantId': m['variantId'],
            'quantity': m['quantity'],
            'priceSnapshot': m['priceSnapshot']?.toString(),
            'productName': m['productName']?.toString(),
            'imageUrl': m['imageUrl']?.toString(),
            'storeId': m['storeId']?.toString(),
            'storeName': m['storeName']?.toString(),
          };
        })
        .toList();
  }

  Future<bool> postCartItem({
    required int productId,
    String? variantId,
    required int quantity,
    required String priceSnapshot,
    required String productName,
    String? imageUrl,
    required String storeId,
    required String storeName,
  }) async {
    if (!BackendOrdersConfig.useBackendCart) return false;
    final body = await _authedPostJson(
      '/cart/items',
      body: <String, dynamic>{
        'productId': productId,
        if (variantId != null && variantId.trim().isNotEmpty) 'variantId': variantId.trim(),
        'quantity': quantity,
        'priceSnapshot': priceSnapshot,
        'productName': productName,
        if (imageUrl != null && imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl.trim(),
        'storeId': storeId,
        'storeName': storeName,
      },
      flow: 'cart_add',
    );
    return body != null;
  }

  Future<bool> patchCartItemQuantity({required String lineId, required int quantity}) async {
    if (!BackendOrdersConfig.useBackendCart) return false;
    final id = lineId.trim();
    if (id.isEmpty) return false;
    final body = await _authedPatchJson(
      '/cart/items/${Uri.encodeComponent(id)}',
      body: <String, dynamic>{'quantity': quantity},
      flow: 'cart_patch',
    );
    return body != null;
  }

  Future<bool> deleteCartItem(String lineId) async {
    if (!BackendOrdersConfig.useBackendCart) return false;
    final id = lineId.trim();
    if (id.isEmpty) return false;
    return _authedDelete('/cart/items/${Uri.encodeComponent(id)}', flow: 'cart_delete');
  }

  Future<bool> deleteCartClear() async {
    if (!BackendOrdersConfig.useBackendCart) return false;
    return _authedDelete('/cart', flow: 'cart_clear');
  }

  Future<Map<String, dynamic>?> fetchUserNotifications({int limit = 50, int offset = 0}) async {
    final body = await _authedGetJson(
      '/notifications',
      query: {'limit': '$limit', 'offset': '$offset'},
      flow: 'notifications_list',
    );
    return body;
  }

  Future<bool> patchNotificationRead(String id) async {
    final nid = id.trim();
    if (nid.isEmpty) return false;
    final body = await _authedPatchJson(
      '/notifications/${Uri.encodeComponent(nid)}/read',
      body: <String, dynamic>{},
      flow: 'notifications_read',
    );
    return body != null;
  }

  Future<Map<String, dynamic>?> postInternalUserNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? referenceId,
    Map<String, dynamic>? metadata,
  }) async {
    return _internalPostJson(
      '/internal/notifications',
      body: <String, dynamic>{
        'userId': userId.trim(),
        'title': title,
        'body': body,
        'type': type,
        if (referenceId != null && referenceId.trim().isNotEmpty) 'referenceId': referenceId.trim(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      },
      flow: 'internal_notification_record',
    );
  }

  Future<Map<String, dynamic>?> postInternalNotificationByEmail({
    required String email,
    required String title,
    required String body,
    required String type,
    String? referenceId,
    Map<String, dynamic>? metadata,
  }) async {
    return _internalPostJson(
      '/internal/notifications/by-email',
      body: <String, dynamic>{
        'email': email.trim(),
        'title': title,
        'body': body,
        'type': type,
        if (referenceId != null && referenceId.trim().isNotEmpty) 'referenceId': referenceId.trim(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      },
      flow: 'internal_notification_by_email',
    );
  }

  Future<Map<String, dynamic>?> postInternalBroadcastAdmins({
    required String title,
    required String body,
    required String type,
    String? referenceId,
    Map<String, dynamic>? metadata,
  }) async {
    return _internalPostJson(
      '/internal/notifications/broadcast-admins',
      body: <String, dynamic>{
        'title': title,
        'body': body,
        'type': type,
        if (referenceId != null && referenceId.trim().isNotEmpty) 'referenceId': referenceId.trim(),
        if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      },
      flow: 'internal_notification_broadcast_admins',
    );
  }

  Future<Map<String, dynamic>?> _internalPostJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 15),
    required String flow,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('NULL_RESPONSE');
    }
    final internalApiKey = const String.fromEnvironment('INTERNAL_API_KEY', defaultValue: '').trim();
    if (internalApiKey.isEmpty) {
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: flow,
        reason: 'missing_internal_api_key',
      );
      throw StateError('NULL_RESPONSE');
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-internal-api-key': internalApiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: flow,
          reason: 'http_${res.statusCode}',
          extra: {'path': path},
        );
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'POST $path',
          statusCode: res.statusCode,
          requestBody: body,
          responseBody: res.body,
        );
        throw StateError('NULL_RESPONSE');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(error: StateError('POST $path failed'), endpoint: 'POST $path', requestBody: body);
      throw StateError('NULL_RESPONSE');
    }
  }

  /// Server RBAC profile (identity token = Firebase only).
  Future<BackendAuthMe?> fetchAuthMe() async {
    final body = await _authedGetJson('/auth/me', flow: 'auth_me');
    if (body == null) throw StateError('NULL_RESPONSE');
    return BackendAuthMe.fromJson(body);
  }

  Future<FeatureState<List<HomeSection>>> fetchHomeSections() async {
    final wrapped = await fetchHomeSectionsVersioned();
    return wrapped.state;
  }

  Future<({FeatureState<List<HomeSection>> state, int version})> fetchHomeSectionsVersioned() async {
    try {
      final res = await _publicGetJson('/home/sections', flow: 'home_sections_list');
      if (res == null) {
        return (
          state: FeatureState.failure<List<HomeSection>>('FAILED_TO_LOAD_HOME_SECTIONS'),
          version: 1,
        );
      }
      final items = res['data'] ?? res['items'];
      if (items is! List) {
        return (
          state: FeatureState.failure<List<HomeSection>>('FAILED_TO_PARSE_HOME_SECTIONS'),
          version: 1,
        );
      }
      final out = <HomeSection>[];
      for (final raw in items) {
        if (raw is! Map) {
          return (
            state: FeatureState.failure<List<HomeSection>>('INVALID_HOME_SECTION_PAYLOAD'),
            version: 1,
          );
        }
        out.add(HomeSection.fromJson(Map<String, dynamic>.from(raw)));
      }
      return (
        state: FeatureState.success(out),
        version: (res['version'] as num?)?.toInt() ?? 1,
      );
    } on Object {
      return (
        state: FeatureState.failure<List<HomeSection>>('FAILED_TO_PARSE_HOME_SECTIONS'),
        version: 1,
      );
    }
  }

  Future<FeatureState<List<SubCategory>>> fetchSubCategories(String sectionId) async {
    final wrapped = await fetchSubCategoriesVersioned(sectionId);
    return wrapped.state;
  }

  Future<({FeatureState<List<SubCategory>> state, int version})> fetchSubCategoriesVersioned(String sectionId) async {
    final sid = sectionId.trim();
    if (sid.isEmpty) {
      return (
        state: FeatureState.failure<List<SubCategory>>('INVALID_HOME_SECTION_ID'),
        version: 1,
      );
    }
    try {
      final res = await _publicGetJson('/home-sections/${Uri.encodeComponent(sid)}/sub-categories', flow: 'sub_categories_list');
      if (res == null) {
        return (
          state: FeatureState.failure<List<SubCategory>>('FAILED_TO_LOAD_SUB_CATEGORIES'),
          version: 1,
        );
      }
      final items = res['data'] ?? res['items'];
      if (items is! List) {
        return (
          state: FeatureState.failure<List<SubCategory>>('FAILED_TO_PARSE_SUB_CATEGORIES'),
          version: 1,
        );
      }
      final out = <SubCategory>[];
      for (final raw in items) {
        if (raw is! Map) {
          return (
            state: FeatureState.failure<List<SubCategory>>('INVALID_SUB_CATEGORY_PAYLOAD'),
            version: 1,
          );
        }
        out.add(SubCategory.fromJson(Map<String, dynamic>.from(raw)));
      }
      return (
        state: FeatureState.success(out),
        version: (res['version'] as num?)?.toInt() ?? 1,
      );
    } on Object {
      return (
        state: FeatureState.failure<List<SubCategory>>('FAILED_TO_PARSE_SUB_CATEGORIES'),
        version: 1,
      );
    }
  }

  Future<FeatureState<List<StoreModel>>> fetchStoresBySubCategory(String subCategoryId) async {
    final id = subCategoryId.trim();
    if (id.isEmpty) return FeatureState.failure('INVALID_SUB_CATEGORY_ID');
    final res = await _publicGetJson('/stores/by-subcategory/${Uri.encodeComponent(id)}', flow: 'stores_by_subcategory');
    if (res == null) return FeatureState.failure('FAILED_TO_LOAD_STORES_BY_SUB_CATEGORY');
    final items = res['items'];
    if (items is! List) return FeatureState.failure('FAILED_TO_PARSE_STORES_BY_SUB_CATEGORY');
    final out = <StoreModel>[];
    for (final raw in items) {
      if (raw is! Map) return FeatureState.failure('INVALID_STORE_PAYLOAD');
      out.add(StoreModel.fromBackendMap(Map<String, dynamic>.from(raw)));
    }
    return FeatureState.success(out);
  }

  Future<FeatureState<List<MarketplaceProduct>>> fetchFilteredProducts({
    String? subCategoryId,
    String? storeId,
    String? sectionId,
    String? search,
    double? minPrice,
    double? maxPrice,
    int limit = 30,
    int offset = 0,
  }) async {
    final query = <String, String>{
      if (subCategoryId != null && subCategoryId.trim().isNotEmpty) 'subCategoryId': subCategoryId.trim(),
      if (storeId != null && storeId.trim().isNotEmpty) 'storeId': storeId.trim(),
      if (sectionId != null && sectionId.trim().isNotEmpty) 'sectionId': sectionId.trim(),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (minPrice != null) 'minPrice': '$minPrice',
      if (maxPrice != null) 'maxPrice': '$maxPrice',
      'limit': '$limit',
      'offset': '$offset',
    };
    final res = await _publicGetJson('/products/filter', query: query, flow: 'products_filter');
    if (res == null) return FeatureState.failure('FAILED_TO_LOAD_FILTERED_PRODUCTS');
    final items = res['items'];
    if (items is! List) return FeatureState.failure('FAILED_TO_PARSE_FILTERED_PRODUCTS');
    final out = <MarketplaceProduct>[];
    for (final raw in items) {
      if (raw is! Map) return FeatureState.failure('INVALID_FILTERED_PRODUCT_PAYLOAD');
      out.add(MarketplaceProduct.fromJson(Map<String, dynamic>.from(raw)));
    }
    return FeatureState.success(out);
  }

  Future<FeatureState<List<SubCategory>>> fetchAdminSubCategories(String sectionId) async {
    final sid = sectionId.trim();
    if (sid.isEmpty) {
      return FeatureState.failure('INVALID_HOME_SECTION_ID');
    }
    final res = await _authedGetJson(
      '/admin/rest/sub-categories',
      query: {'sectionId': sid},
      flow: 'admin_sub_categories_list',
    );
    if (res == null) {
      return FeatureState.failure('FAILED_TO_LOAD_ADMIN_SUB_CATEGORIES');
    }
    final items = res['items'];
    if (items is! List) {
      return FeatureState.failure('FAILED_TO_PARSE_ADMIN_SUB_CATEGORIES');
    }
    final out = <SubCategory>[];
    for (final raw in items) {
      if (raw is! Map) {
        return FeatureState.failure('INVALID_SUB_CATEGORY_PAYLOAD');
      }
      out.add(SubCategory.fromJson(Map<String, dynamic>.from(raw)));
    }
    return FeatureState.success(out);
  }

  Future<FeatureState<String>> createAdminSubCategory({
    required String homeSectionId,
    required String name,
    String? image,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    final res = await _authedPostJson(
      '/admin/rest/sub-categories',
      body: <String, dynamic>{
        'homeSectionId': homeSectionId.trim(),
        'name': name.trim(),
        'image': image,
        'sortOrder': sortOrder,
        'isActive': isActive,
      },
      flow: 'admin_sub_category_create',
    );
    if (res == null) {
      return FeatureState.failure('FAILED_TO_CREATE_SUB_CATEGORY');
    }
    final id = res['id']?.toString() ?? '';
    if (id.trim().isEmpty) {
      return FeatureState.failure('FAILED_TO_CREATE_SUB_CATEGORY');
    }
    return FeatureState.success(id.trim());
  }

  Future<FeatureState<FeatureUnit>> patchAdminSubCategory({
    required String id,
    String? homeSectionId,
    String? name,
    String? image,
    int? sortOrder,
    bool? isActive,
  }) async {
    final res = await _authedPatchJson(
      '/admin/rest/sub-categories/${Uri.encodeComponent(id.trim())}',
      body: <String, dynamic>{
        if (homeSectionId != null) 'homeSectionId': homeSectionId.trim(),
        if (name != null) 'name': name.trim(),
        if (image != null) 'image': image,
        if (sortOrder != null) 'sortOrder': sortOrder,
        if (isActive != null) 'isActive': isActive,
      },
      flow: 'admin_sub_category_patch',
    );
    if (res == null) {
      return FeatureState.failure('FAILED_TO_PATCH_SUB_CATEGORY');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteAdminSubCategory(String id) async {
    final ok = await _authedDelete('/admin/rest/sub-categories/${Uri.encodeComponent(id.trim())}', flow: 'admin_sub_category_delete');
    if (!ok) {
      return FeatureState.failure('FAILED_TO_DELETE_SUB_CATEGORY');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<JsonList> fetchAdminTechnicians({int limit = 200, int offset = 0}) async {
    final body = await _authedGetJson(
      '/admin/rest/technicians',
      query: {'limit': '$limit', 'offset': '$offset'},
      flow: 'admin_technicians_list',
    );
    final items = body?['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> fetchAdminTechnicianById(String id) async {
    final v = id.trim();
    if (v.isEmpty) throw StateError('NULL_RESPONSE');
    return _authedGetJson('/admin/rest/technicians/${Uri.encodeComponent(v)}', flow: 'admin_technician_by_id');
  }

  Future<bool> upsertAdminTechnician(String id, Map<String, dynamic> payload) async {
    final v = id.trim();
    if (v.isEmpty) return false;
    final body = await _authedPatchJson(
      '/admin/rest/technicians/${Uri.encodeComponent(v)}',
      body: payload,
      flow: 'admin_technician_upsert',
    );
    return body != null;
  }

  Future<JsonList> fetchTechSpecialties() async {
    final body = await _authedGetJson('/tech-specialties', flow: 'tech_specialties_list');
    final items = body?['items'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
