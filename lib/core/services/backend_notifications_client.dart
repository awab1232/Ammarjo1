import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';
import '../contracts/feature_state.dart';
import 'firebase_auth_header_provider.dart';

final class BackendNotificationsClient {
  BackendNotificationsClient._();
  static final BackendNotificationsClient instance = BackendNotificationsClient._();

  Future<FeatureState<List<Map<String, dynamic>>>> fetchNotifications({int limit = 50, int offset = 0}) async {
    final body = await _authedGet('/notifications', query: {'limit': '$limit', 'offset': '$offset'});
    final items = body?['items'];
    if (items is! List) return FeatureState.failure('Invalid notifications payload.');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<bool> markRead(String id) async {
    final nid = id.trim();
    if (nid.isEmpty) return false;
    final body = await _authedPatch('/notifications/${Uri.encodeComponent(nid)}/read', <String, dynamic>{});
    return body != null;
  }

  Future<Map<String, dynamic>?> sendInternal(Map<String, dynamic> payload) async {
    return _internalPost('/internal/notifications', payload);
  }

  Future<bool> registerDeviceToken(String token) async {
    final t = token.trim();
    if (t.isEmpty) return false;
    final req = await _request('/notifications/register-device');
    if (req == null) return false;
    final headers = <String, String>{...req.$2, 'Content-Type': 'application/json'};
    final platform = _platformLabel();
    final res = await http.post(
      req.$1,
      headers: headers,
      body: jsonEncode(<String, dynamic>{'token': t, 'platform': platform}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<FeatureState<Map<String, dynamic>>> fetchUpdates({
    required DateTime since,
    int limit = 20,
  }) async {
    try {
      final body = await _authedGet(
        '/notifications/updates',
        query: <String, String>{
          'since': since.toUtc().toIso8601String(),
          'limit': '$limit',
        },
      );
      if (body == null) return FeatureState.failure('NULL_RESPONSE');
      return FeatureState.success(body);
    } on Object {
      return FeatureState.failure('NULL_RESPONSE');
    }
  }

  Future<Map<String, dynamic>?> _authedGet(String path, {Map<String, String>? query}) async {
    final req = await _request(path, query: query);
    if (req == null) throw StateError('NULL_RESPONSE');
    final res = await http.get(req.$1, headers: req.$2);
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('NULL_RESPONSE');
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw StateError('NULL_RESPONSE');
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return defaultTargetPlatform.name.toLowerCase();
    }
  }

  Future<Map<String, dynamic>?> _authedPatch(String path, Map<String, dynamic> body) async {
    final req = await _request(path);
    if (req == null) throw StateError('NULL_RESPONSE');
    final headers = <String, String>{...req.$2, 'Content-Type': 'application/json'};
    final res = await http.patch(req.$1, headers: headers, body: jsonEncode(body));
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('NULL_RESPONSE');
    if (res.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> _internalPost(String path, Map<String, dynamic> body) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    final key = const String.fromEnvironment('INTERNAL_API_KEY', defaultValue: '').trim();
    if (base.isEmpty || key.isEmpty) throw StateError('NULL_RESPONSE');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    final res = await http.post(
      uri,
      headers: <String, String>{'Content-Type': 'application/json', 'x-internal-api-key': key},
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('NULL_RESPONSE');
    if (res.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<(Uri, Map<String, String>)?> _request(String path, {Map<String, String>? query}) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) throw StateError('NULL_RESPONSE');
    final authHeaders = await FirebaseAuthHeaderProvider.requireAuthHeaders(
      reason: 'backend_notifications:$path',
    );
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    FirebaseAuthHeaderProvider.logRequestHeaders(method: 'REQUEST', uri: uri, headers: authHeaders);
    return (uri, authHeaders);
  }
}
