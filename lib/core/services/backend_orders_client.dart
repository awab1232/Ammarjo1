import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/backend_orders_config.dart';
import '../logging/backend_fallback_logger.dart';
import '../models/backend_auth_me.dart';
import '../models/home_section.dart';
import '../models/sub_category.dart';
import '../models/marketplace_product.dart';
import '../session/backend_identity_controller.dart';
import '../../features/stores/domain/store_model.dart';
import '../monitoring/sentry_safe.dart';
import '../session/user_session.dart';
import '../contracts/feature_state.dart';
import '../contracts/feature_unit.dart';
import 'firebase_auth_header_provider.dart';

typedef JsonMap = Map<String, dynamic>;
typedef JsonList = List<JsonMap>;
typedef VersionedJsonList = ({JsonList items, int version});

/// HTTP client for the shadow orders API (Bearer = Firebase ID token).
final class BackendOrdersClient {
  BackendOrdersClient._();
  static final BackendOrdersClient instance = BackendOrdersClient._();

  bool _isAdminPath(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('/admin/');
  }

  Future<bool> _allowPath(String path) async {
    if (!_isAdminPath(path)) return true;
    final identity = BackendIdentityController.instance;
    if (identity.me == null) {
      await identity.refresh();
    }
    final ok = identity.isBackendFullAdmin;
    if (!ok) {
      debugPrint('[BackendOrdersClient] blocked admin path for non-admin: $path');
    }
    return ok;
  }

  Map<String, dynamic>? _safeMap(Map<String, dynamic>? source) {
    if (source == null) throw StateError('unexpected_empty_response');
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
    if (!BackendOrdersConfig.useBackendOrdersWrite) throw StateError('unexpected_empty_response');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('orders_write_primary');
      throw StateError('unexpected_empty_response');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('unexpected_empty_response');
    final String token = await _idToken(user);
    if (token.isEmpty) throw StateError('unexpected_empty_response');

    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/orders');
    final Duration t = BackendOrdersConfig.backendOrdersWriteTimeout;
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'POST', uri: uri, headers: headers);
      final res = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(t);
      FirebaseAuthHeaderProvider.logDebugResponse('POST /orders (primary)', res.statusCode, res.body);
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
        throw StateError('unexpected_empty_response');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) throw StateError('unexpected_empty_response');
      final m = Map<String, dynamic>.from(decoded);
      final id = m['id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
      final order = m['order'];
      if (order is Map) {
        final om = Map<String, dynamic>.from(order);
        final oid = om['orderId']?.toString().trim();
        if (oid != null && oid.isNotEmpty) return oid;
      }
      throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    } on StateError {
      rethrow;
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
      throw StateError('unexpected_empty_response');
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
    final String token = await _idToken(user);
    if (token.isEmpty) return;

    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/orders');
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'POST', uri: uri, headers: headers);
      final res = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      );
      FirebaseAuthHeaderProvider.logDebugResponse('POST /orders (shadow)', res.statusCode, res.body);
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
    } on StateError {
      rethrow;
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
    if (!BackendOrdersConfig.useBackendOrdersRead) throw StateError('unexpected_empty_response');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('orders_read_get');
      throw StateError('unexpected_empty_response');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('unexpected_empty_response');
    final String token = await _idToken(user);
    if (token.isEmpty) throw StateError('unexpected_empty_response');

    final uri = Uri.parse(
      '${base.replaceAll(RegExp(r'/$'), '')}/orders/${Uri.encodeComponent(orderId)}',
    );
    final Duration t = timeout ?? BackendOrdersConfig.backendOrdersReadTimeout;
    try {
      final res = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(t);
      FirebaseAuthHeaderProvider.logDebugResponse('GET /orders/$orderId', res.statusCode, res.body);
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
        throw StateError('unexpected_empty_response');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    } on StateError {
      rethrow;
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
      throw StateError('unexpected_empty_response');
    }
  }

  /// POST `/orders/:id/retry-assignment` — customer retry after `no_driver_found`.
  Future<bool> postOrderRetryAssignment(String orderId) async {
    if (!BackendOrdersConfig.useBackendOrdersRead) return false;
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('orders_retry_assignment');
      return false;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final String token = await _idToken(user);
    if (token.isEmpty) throw StateError('unexpected_empty_response');

    final uri = Uri.parse(
      '${base.replaceAll(RegExp(r'/$'), '')}/orders/${Uri.encodeComponent(orderId)}/retry-assignment',
    );
    final Duration t = BackendOrdersConfig.backendOrdersWriteTimeout;
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: '{}',
        )
        .timeout(t);
    FirebaseAuthHeaderProvider.logDebugResponse('POST /orders/$orderId/retry-assignment', res.statusCode, res.body);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  /// `PATCH /orders/:id/status` — عميل (إلغاء)، متجر، أو مسار مرخّص.
  Future<bool> patchOrderStatus({
    required String orderId,
    required String statusEnglish,
  }) async {
    final path = '/orders/${Uri.encodeComponent(orderId.trim())}/status';
    await _authedPatchJson(
      path,
      body: <String, dynamic>{'status': statusEnglish.trim().toLowerCase()},
      flow: 'orders_patch_status',
    );
    return true;
  }

  Future<JsonList?> fetchOrdersForCurrentUser({
    int limit = 20,
    String? cursor,
  }) async {
    if (!BackendOrdersConfig.useBackendOrdersRead) throw StateError('unexpected_empty_response');
    if (!UserSession.isLoggedIn) throw StateError('unexpected_empty_response');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) throw StateError('unexpected_empty_response');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/orders').replace(
      queryParameters: {
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    final headers = await FirebaseAuthHeaderProvider.requireAuthHeaders(reason: 'orders_read_list');
    FirebaseAuthHeaderProvider.logRequestHeaders(method: 'GET', uri: uri, headers: headers);
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    FirebaseAuthHeaderProvider.logDebugResponse('BackendOrdersClient GET /orders', res.statusCode, res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('unexpected_empty_response');
    }
    final trimmed = res.body.trim();
    if (trimmed.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on Object {
      throw StateError('unexpected_empty_response');
    }
    if (decoded is List) {
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    final body = decoded is Map<String, dynamic>
        ? decoded
        : (decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{});
    final itemsRaw = body['items'];
    final List<dynamic> itemsList = itemsRaw is List ? itemsRaw : const <dynamic>[];
    return itemsList.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<bool> saveUserLocation({
    required double lat,
    required double lng,
  }) async {
    final body = await _authedPostJson(
      '/users/location',
      body: <String, dynamic>{'lat': lat, 'lng': lng},
      flow: 'user_location_update',
    );
    return body != null && body['ok'] == true;
  }

  Future<String> _idToken(User user) async {
    try {
      final token = await FirebaseAuthHeaderProvider.requireIdToken(reason: 'backend_orders_id_token');
      debugPrint(
        '[AUTH-HEADER] reason=backend_orders_id_token token_is_null=false len=${token.trim().length}',
      );
      return token;
    } on Object {
      debugPrint('BackendOrders: getIdToken failed');
      throw StateError('token_unavailable');
    }
  }

  Future<Map<String, dynamic>?> _authedPostJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 20),
    required String flow,
  }) async {
    if (!await _allowPath(path)) throw StateError('unexpected_empty_response');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('unexpected_empty_response');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('unexpected_empty_response');
    final token = await _idToken(user);
    if (token.isEmpty) throw StateError('unexpected_empty_response');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'POST', uri: uri, headers: headers);
      final res = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      FirebaseAuthHeaderProvider.logDebugResponse('POST $path', res.statusCode, res.body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        String reason = 'HTTP_${res.statusCode}';
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            final msg = decoded['message']?.toString().trim() ?? '';
            if (msg.isNotEmpty) {
              reason = msg;
            }
          }
        } on Object {
          // Keep default reason when body is not JSON.
        }
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
        throw StateError(reason);
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    } on StateError {
      rethrow;
    } on Object {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: flow,
        reason: 'unknown_error',
        extra: {'path': path},
      );
      await _captureApiFailure(error: StateError('POST $path failed'), endpoint: 'POST $path', requestBody: body);
      throw StateError('REQUEST_FAILED');
    }
  }

  Future<Map<String, dynamic>?> _authedPatchJson(
    String path, {
    required Map<String, dynamic> body,
    Duration timeout = const Duration(seconds: 20),
    required String flow,
  }) async {
    if (!await _allowPath(path)) throw StateError('unexpected_empty_response');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('unexpected_empty_response');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('unexpected_empty_response');
    final token = await _idToken(user);
    if (token.isEmpty) throw StateError('unexpected_empty_response');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'PATCH', uri: uri, headers: headers);
      final res = await http
          .patch(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      FirebaseAuthHeaderProvider.logDebugResponse('PATCH $path', res.statusCode, res.body);
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
        throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    }
  }

  Future<bool> _authedDelete(
    String path, {
    Duration timeout = const Duration(seconds: 20),
    required String flow,
  }) async {
    if (!await _allowPath(path)) return false;
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      return false;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final token = await _idToken(user);
    if (token.isEmpty) return false;
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    try {
      final headers = <String, String>{'Authorization': 'Bearer $token'};
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'DELETE', uri: uri, headers: headers);
      final res = await http.delete(uri, headers: headers).timeout(timeout);
      FirebaseAuthHeaderProvider.logDebugResponse('DELETE $path', res.statusCode, res.body);
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
    if (!await _allowPath(path)) throw StateError('unexpected_empty_response');
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      throw StateError('unexpected_empty_response');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('unexpected_empty_response');
    final token = await _idToken(user);
    if (token.isEmpty) throw StateError('unexpected_empty_response');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    try {
      final headers = <String, String>{'Authorization': 'Bearer $token'};
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'GET', uri: uri, headers: headers);
      final res = await http.get(uri, headers: headers).timeout(timeout);
      FirebaseAuthHeaderProvider.logDebugResponse('GET (authed) $path', res.statusCode, res.body);
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
        throw StateError('unexpected_empty_response');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) {
        return <String, dynamic>{'items': decoded};
      }
      throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    try {
      final headers = await FirebaseAuthHeaderProvider.authHeadersIfSignedIn(reason: 'backend_orders_public_get:$path');
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'GET', uri: uri, headers: headers);
      final res = await http.get(uri, headers: headers).timeout(timeout);
      FirebaseAuthHeaderProvider.logDebugResponse('GET (public) $path', res.statusCode, res.body);
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
        throw StateError('unexpected_empty_response');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) {
        return <String, dynamic>{'items': decoded};
      }
      throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    }
  }

  /// Same as [_publicGetJson] but **never throws** — returns `null` on network/HTTP/parse issues.
  /// Used for home/marketing endpoints so the UI never crashes on empty or odd payloads.
  Future<Map<String, dynamic>?> _publicGetJsonOrNull(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
    required String flow,
    bool logApiResponse = false,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing(flow);
      debugPrint('[BackendOrdersClient] $flow: skipped (no base URL)');
      return null;
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    try {
      final headers = await FirebaseAuthHeaderProvider.authHeadersIfSignedIn(
        reason: 'backend_orders_public_get_or_null:$path',
      );
      FirebaseAuthHeaderProvider.logRequestHeaders(method: 'GET', uri: uri, headers: headers);
      final res = await http.get(uri, headers: headers).timeout(timeout);
      FirebaseAuthHeaderProvider.logDebugResponse('GET (public safe) $path', res.statusCode, res.body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[BackendOrdersClient] $flow: HTTP ${res.statusCode}');
        return null;
      }
      final rawBody = res.body.trim();
      if (rawBody.isEmpty) {
        debugPrint('[BackendOrdersClient] $flow: empty response body');
        return null;
      }
      if (logApiResponse) {
        final preview = rawBody.length > 2000 ? '${rawBody.substring(0, 2000)}…(truncated)' : rawBody;
        debugPrint('[API RESPONSE] $flow GET $path status=${res.statusCode} bytes=${rawBody.length} body=$preview');
      }
      final decoded = jsonDecode(rawBody);
      if (decoded == null) {
        debugPrint('[BackendOrdersClient] $flow: JSON null');
        return null;
      }
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) {
        return <String, dynamic>{'items': decoded};
      }
      debugPrint('[BackendOrdersClient] $flow: unexpected JSON root ${decoded.runtimeType}');
      return null;
    } on Object catch (e, st) {
      debugPrint('[BackendOrdersClient] $flow: safe GET failed: $e');
      if (kDebugMode) {
        debugPrint('$st');
      }
      return null;
    }
  }

  List<dynamic> _homeSectionItemsFromEnvelope(Object? json) {
    if (json == null) return <dynamic>[];
    if (json is List) return json;
    if (json is Map) {
      final m = json is Map<String, dynamic> ? json : Map<String, dynamic>.from(json);
      final items = m['items'] ?? m['data'];
      if (items is List) return items;
    }
    return <dynamic>[];
  }

  /// Accepts either a JSON array root or `{"items":[...]}` (and tolerates bad rows).
  List<dynamic> _storeRowsFromResponseJson(Object? responseJson, String debugTag) {
    debugPrint('[BackendOrdersClient] $debugTag responseJson runtimeType: ${responseJson.runtimeType}');
    if (responseJson is List) return responseJson;
    if (responseJson is Map) {
      final m = responseJson is Map<String, dynamic>
          ? responseJson
          : Map<String, dynamic>.from(responseJson);
      final items = m['items'] ?? m['data'];
      if (items is List) return items;
    }
    return <dynamic>[];
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
    final rows = _storeRowsFromResponseJson(body, 'fetchStores');
    final out = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      try {
        final row = Map<String, dynamic>.from(raw);
        if (category != null && category.trim().isNotEmpty) {
          if ((row['category']?.toString() ?? '').trim() != category.trim()) continue;
        }
        out.add(row);
      } on Object {
        continue;
      }
    }
    return out;
  }

  /// Public (unauthenticated) store directory used by the mobile home page
  /// when there is no signed-in user, or as a fallback after an auth failure.
  /// The backend falls back to mock Arabic demo stores if the DB is empty.
  Future<JsonList?> fetchStoresPublic({
    String? category,
    int limit = 50,
  }) async {
    final body = await _publicGetJsonOrNull(
      '/stores/public',
      query: {'limit': '$limit'},
      flow: 'stores_list_public',
      logApiResponse: true,
    );
    if (body == null) {
      debugPrint('[BackendOrdersClient] fetchStoresPublic: no JSON, returning empty list');
      return <Map<String, dynamic>>[];
    }
    final rows = _storeRowsFromResponseJson(body, 'fetchStoresPublic');
    final out = <Map<String, dynamic>>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      try {
        final row = Map<String, dynamic>.from(raw);
        if (category != null && category.trim().isNotEmpty) {
          if ((row['category']?.toString() ?? '').trim() != category.trim()) continue;
        }
        out.add(row);
      } on Object {
        continue;
      }
    }
    return out;
  }

  Future<JsonList?> fetchStoreTypes() async {
    final data = await fetchStoreTypesVersioned();
    return data.items;
  }

  Future<VersionedJsonList> fetchStoreTypesVersioned() async {
    try {
      final body = await _publicGetJson('/stores/store-types', flow: 'stores_types_public');
      if (body == null) throw StateError('unexpected_empty_response');
      final raw = body['data'] ?? body['items'];
      if (raw is! List) throw StateError('unexpected_empty_response');
      final items = raw;
      final list = items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final version = (body['version'] as num?)?.toInt() ?? 1;
      return (items: list, version: version);
    } on Object catch (e, st) {
      debugPrint('[BackendOrdersClient] store-types: $e');
      if (kDebugMode) {
        debugPrint('$st');
      }
      throw StateError('unexpected_empty_response');
    }
  }

  Future<JsonList?> fetchPendingStores({int limit = 200, int offset = 0}) async {
    final body = await _authedGetJson(
      '/admin/rest/stores',
      query: {'limit': '$limit', 'offset': '$offset'},
      flow: 'admin_stores_pending_list',
    );
    final items = body?['items'];
    if (items is! List) throw StateError('unexpected_empty_response');
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
    final body = await _publicGetJson(
      '/stores/${Uri.encodeComponent(storeId.trim())}/categories',
      flow: 'store_categories',
    );
    if (body == null) throw StateError('unexpected_empty_response');
    final items = body['items'];
    if (items is! List) throw StateError('unexpected_empty_response');
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<JsonList?> fetchProductsByStore({
    required String storeId,
    int limit = 100,
    String? cursor,
  }) async {
    final dynamic json = await _publicGetJson(
      '/products',
      query: {
        'storeId': storeId.trim(),
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
      flow: 'products_by_store_public',
    );
    if (json == null) throw StateError('unexpected_empty_response');
    final List<dynamic> rows = json is List
        ? json
        : (json is Map && json['items'] is List
            ? json['items'] as List<dynamic>
            : (json is Map && json['data'] is List ? json['data'] as List<dynamic> : <dynamic>[]));
    if (rows.isEmpty && json is! Map) throw StateError('unexpected_empty_response');
    return rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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
    final body = await _publicGetJson(
      '/products',
      query: {'limit': '$limit'},
      flow: 'products_public_list',
    );
    if (body == null) throw StateError('unexpected_empty_response');
    final rows = _storeRowsFromResponseJson(body, 'fetchPublicProducts');
    if (rows.isEmpty) throw StateError('unexpected_empty_response');
    return rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// `GET /banners` may return a JSON array or `{ "items": [...] }` (legacy).
  /// Never throws; returns `null` on failure so callers can show placeholders.
  Future<JsonList?> fetchBanners() async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('public_banners');
      return null;
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/banners');
    try {
      final res = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json; charset=utf-8',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BackendFallbackLogger.logBackendFallbackTriggered(
          flow: 'public_banners',
          reason: 'http_${res.statusCode}',
          extra: const {'path': '/banners'},
        );
        return null;
      }
      final trimmed = res.body.trim();
      if (trimmed.isEmpty) {
        debugPrint('[BackendOrdersClient] public_banners: empty body');
        return null;
      }
      final decoded = jsonDecode(trimmed);
      if (decoded == null) {
        return null;
      }
      List<dynamic>? raw;
      if (decoded is List) {
        raw = decoded;
      } else if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        final items = m['items'] ?? m['data'];
        if (items is List) raw = items;
      }
      if (raw == null) return null;
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on Object catch (e, st) {
      if (kDebugMode) {
        debugPrint('BackendOrders: fetchBanners failed: $e');
        debugPrint('$st');
      }
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'public_banners',
        reason: 'parse_or_network',
        extra: const {'path': '/banners'},
      );
      return null;
    }
  }

  static const Duration _homeCmsTtl = Duration(minutes: 3);
  Map<String, dynamic>? _homeCmsCache;
  DateTime? _homeCmsFetchedAt;
  Future<Map<String, dynamic>?>? _homeCmsInFlight;

  /// Marketing layout: primary slider (3), offers strip, bottom banner (`GET /home/cms`).
  /// In-memory TTL + single in-flight request to avoid duplicate calls when multiple widgets mount together.
  Future<Map<String, dynamic>?> fetchHomeCms({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _homeCmsCache != null &&
        _homeCmsFetchedAt != null &&
        now.difference(_homeCmsFetchedAt!) <= _homeCmsTtl) {
      return _homeCmsCache;
    }
    if (!forceRefresh && _homeCmsInFlight != null) {
      return _homeCmsInFlight!;
    }
    Future<Map<String, dynamic>?> run() async {
      return _publicGetJsonOrNull('/home/cms', flow: 'public_home_cms');
    }

    if (forceRefresh) {
      _homeCmsInFlight = null;
      final fresh = await run();
      _homeCmsCache = fresh;
      _homeCmsFetchedAt = DateTime.now();
      return fresh;
    }

    _homeCmsInFlight = run().then((v) {
      _homeCmsCache = v;
      _homeCmsFetchedAt = DateTime.now();
      _homeCmsInFlight = null;
      return v;
    });
    return _homeCmsInFlight!;
  }

  Future<void> postChatMessageSent({
    required String conversationId,
    required String senderId,
    required String targetUserId,
    required String messageId,
    required String messagePreview,
    String type = 'general',
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final token = await _idToken(user);
    if (token.isEmpty) return;
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/chat/events/message-sent');
    final payload = <String, dynamic>{
      'conversationId': conversationId,
      'senderId': senderId,
      'receiverId': targetUserId,
      'targetUserId': targetUserId,
      'messageId': messageId,
      'messagePreview': messagePreview,
      'type': type,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      debugPrint('[CHAT-ERROR] sending chat event payload=$payload');
      var res = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('[CHAT-ERROR] chat event failed status=${res.statusCode} body=${res.body}');
        res = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          debugPrint('[CHAT-ERROR] chat event retry failed status=${res.statusCode} body=${res.body}');
        } else {
          debugPrint('[CHAT-ERROR] chat event retry succeeded');
        }
      } else {
        debugPrint('[CHAT-ERROR] chat event sent status=${res.statusCode}');
      }
    } on Object {
      debugPrint('[CHAT-ERROR] message-sent event post exception');
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
    if (body == null) throw StateError('unexpected_empty_response');
    final hits = body['hits'];
    if (hits is! List) throw StateError('unexpected_empty_response');
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
    if (token.isEmpty) {
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
    if (body == null) throw StateError('unexpected_empty_response');
    final hits = body['hits'];
    if (hits is! List) throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    }
    final internalApiKey = const String.fromEnvironment('INTERNAL_API_KEY', defaultValue: '').trim();
    if (internalApiKey.isEmpty) {
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: flow,
        reason: 'missing_internal_api_key',
      );
      throw StateError('unexpected_empty_response');
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
        throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    }
  }

  Future<Map<String, dynamic>?> fetchAnalyticsOverview() async {
    final body = await _internalGetJson('/internal/analytics/summary', flow: 'analytics_overview');
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    throw StateError('unexpected_empty_response');
  }

  Future<JsonList?> fetchAnalyticsDaily({int days = 30}) async {
    final body = await _internalGetJson(
      '/internal/analytics/timeline',
      query: {'days': '$days'},
      flow: 'analytics_daily',
    );
    if (body is! List) throw StateError('unexpected_empty_response');
    return body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<JsonList?> fetchAnalyticsStores({int limit = 10}) async {
    final body = await _internalGetJson(
      '/internal/analytics/top-technicians',
      query: {'limit': '$limit'},
      flow: 'analytics_stores',
    );
    if (body is! List) throw StateError('unexpected_empty_response');
    return body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<JsonList?> fetchAnalyticsRevenue({int limit = 50}) async {
    final body = await _internalGetJson(
      '/internal/analytics/slow-requests',
      query: {'limit': '$limit'},
      flow: 'analytics_revenue',
    );
    if (body is! List) throw StateError('unexpected_empty_response');
    return body.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<JsonList?> fetchCart() async {
    if (!BackendOrdersConfig.useBackendCart) throw StateError('unexpected_empty_response');
    final body = await _authedGetJson('/cart', flow: 'cart_list');
    final items = body?['items'];
    if (items is! List) throw StateError('unexpected_empty_response');
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
    if (!BackendOrdersConfig.useBackendCart) throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    }
    final internalApiKey = const String.fromEnvironment('INTERNAL_API_KEY', defaultValue: '').trim();
    if (internalApiKey.isEmpty) {
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: flow,
        reason: 'missing_internal_api_key',
      );
      throw StateError('unexpected_empty_response');
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
        throw StateError('unexpected_empty_response');
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
      throw StateError('unexpected_empty_response');
    }
  }

  /// Server RBAC profile (identity token = Firebase only).
  Future<BackendAuthMe?> fetchAuthMe() async {
    try {
      final body = await _authedGetJson('/auth/me', flow: 'auth_me');
      if (body == null) throw StateError('unexpected_empty_response');
      return BackendAuthMe.fromJson(body);
    } on Object {
      throw StateError('unexpected_empty_response');
    }
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
      final items = _homeSectionItemsFromEnvelope(res);
      final out = <HomeSection>[];
      for (final raw in items) {
        if (raw is! Map) continue;
        try {
          out.add(HomeSection.fromJson(Map<String, dynamic>.from(raw)));
        } on Object {
          continue;
        }
      }
      if (out.isEmpty) {
        debugPrint('home sections empty');
      }
      return (
        state: FeatureState.success(out),
        version: (res['version'] as num?)?.toInt() ?? 1,
      );
    } on Object catch (e, st) {
      debugPrint('home sections failed');
      if (kDebugMode) {
        debugPrint('$e\n$st');
      }
      return (
        state: FeatureState.failure<List<HomeSection>>('FAILED_TO_LOAD_HOME_SECTIONS', e),
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
      final res = await _publicGetJson(
        '/home/home-sections/${Uri.encodeComponent(sid)}/sub-categories',
        flow: 'sub_categories_list',
      );
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
    try {
      final res = await _publicGetJson(
        '/stores/by-subcategory/${Uri.encodeComponent(id)}',
        flow: 'stores_by_subcategory',
      );
      final rows = _storeRowsFromResponseJson(res, 'fetchStoresBySubCategory');
      final out = <StoreModel>[];
      for (final raw in rows) {
        if (raw is! Map) continue;
        try {
          out.add(StoreModel.fromBackendMap(Map<String, dynamic>.from(raw)));
        } on Object {
          continue;
        }
      }
      return FeatureState.success(out);
    } on Object catch (e) {
      return FeatureState.failure('FAILED_TO_LOAD_STORES_BY_SUBCATEGORY', e);
    }
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
    if (v.isEmpty) throw StateError('unexpected_empty_response');
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
    try {
      final body = await _authedGetJson('/tech-specialties', flow: 'tech_specialties_list');
      final items = body?['items'];
      if (items is! List) return const <Map<String, dynamic>>[];
      return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } on Object {
      return const <Map<String, dynamic>>[
        {'id': 'plumbing', 'name': 'سباكة', 'categoryId': 'plumber'},
        {'id': 'electricity', 'name': 'كهرباء', 'categoryId': 'electrician'},
        {'id': 'conditioning', 'name': 'تكييف', 'categoryId': 'ac'},
        {'id': 'carpentry', 'name': 'نجارة', 'categoryId': 'carpenter'},
      ];
    }
  }

  // ——— Driver panel (Firebase + [BackendOrdersConfig] base URL) ———

  Future<Map<String, dynamic>?> fetchDriverWorkbench() =>
      _authedGetJson('/drivers/workbench', flow: 'driver_workbench');

  Future<Map<String, dynamic>?> postDriverRegister({String? name, String? phone}) => _authedPostJson(
        '/drivers/register',
        body: <String, dynamic>{
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
        flow: 'driver_register',
      );

  Future<Map<String, dynamic>?> postDriverStatus(String status) =>
      _authedPostJson('/drivers/status', body: <String, dynamic>{'status': status}, flow: 'driver_status');

  Future<Map<String, dynamic>?> postDriverLocation({required double lat, required double lng}) => _authedPostJson(
        '/drivers/location',
        body: <String, dynamic>{'lat': lat, 'lng': lng},
        flow: 'driver_location',
      );

  Future<Map<String, dynamic>?> postDriverAcceptOrder(String orderId) => _authedPostJson(
        '/drivers/accept-order',
        body: <String, dynamic>{'orderId': orderId.trim()},
        flow: 'driver_accept',
      );

  Future<Map<String, dynamic>?> postDriverRejectOrder(String orderId) => _authedPostJson(
        '/drivers/reject-order',
        body: <String, dynamic>{'orderId': orderId.trim()},
        flow: 'driver_reject',
      );

  Future<Map<String, dynamic>?> postDriverOnTheWay(String orderId) => _authedPostJson(
        '/drivers/on-the-way',
        body: <String, dynamic>{'orderId': orderId.trim()},
        flow: 'driver_on_way',
      );

  Future<Map<String, dynamic>?> postDriverCompleteOrder(String orderId) => _authedPostJson(
        '/drivers/complete-order',
        body: <String, dynamic>{'orderId': orderId.trim()},
        flow: 'driver_complete',
      );

  /// POST `/drivers/request` — driver onboarding application (after Firebase sign-in).
  Future<Map<String, dynamic>?> postDriverOnboardingRequest({
    required String fullName,
    required String phone,
    required String identityImageUrl,
  }) =>
      _authedPostJson(
        '/drivers/request',
        body: <String, dynamic>{
          'fullName': fullName.trim(),
          'phone': phone.trim(),
          'identityImageUrl': identityImageUrl.trim(),
        },
        flow: 'driver_onboarding_request',
      );

  /// POST `/upload` — multipart image; returns `{ url }` (same [BackendOrdersConfig] base URL).
  Future<Map<String, dynamic>?> postUploadIdentityImage({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('driver_upload');
      throw StateError('unexpected_empty_response');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('unexpected_empty_response');
    final token = await _idToken(user);
    if (token.isEmpty) throw StateError('unexpected_empty_response');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}/upload');
    try {
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName.replaceAll(RegExp(r'[^\w.\-]'), '_'),
        ),
      );
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await _captureApiFailure(
          error: StateError('HTTP_${res.statusCode}'),
          endpoint: 'POST /upload',
          statusCode: res.statusCode,
          responseBody: res.body,
        );
        throw StateError('unexpected_empty_response');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw StateError('unexpected_empty_response');
    } on Object {
      await _captureApiFailure(error: StateError('POST /upload failed'), endpoint: 'POST /upload');
      throw StateError('unexpected_empty_response');
    }
  }
}
