import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';
import '../contracts/feature_state.dart';
import 'firebase_auth_header_provider.dart';

final class BackendUserClient {
  BackendUserClient._();
  static final BackendUserClient instance = BackendUserClient._();
  static Future<Map<String, dynamic>?> getMe() => instance.fetchMe();

  Future<Map<String, dynamic>?> fetchMe() async {
    return _authedGet('/auth/me');
  }

  /// Loads profile through authenticated identity only.
  Future<Map<String, dynamic>?> fetchUserById(String uid) async {
    if (uid.trim().isEmpty) throw StateError('invalid_user_id');
    return _authedGet('/users/me');
  }

  Future<bool> patchUser(String uid, Map<String, dynamic> fields) async {
    if (uid.trim().isEmpty || fields.isEmpty) throw StateError('invalid_user_payload');
    final body = await _authedPatch('/users/me', fields);
    return body != null;
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchTechSpecialties() async {
    return FeatureState.failure('Tech specialties endpoint is not wired on backend.');
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchUserFavorites(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return FeatureState.failure('User id is required.');
    return FeatureState.failure('Favorites endpoint is not wired on backend.');
  }

  Future<bool> putUserFavorite(String uid, Map<String, dynamic> payload) async {
    throw StateError('Favorites endpoint is not wired on backend.');
  }

  Future<bool> deleteUserFavorite(String uid, String productId) async {
    throw StateError('Favorites endpoint is not wired on backend.');
  }

  Future<Map<String, dynamic>?> _authedGet(String path) async {
    final req = await _request(path);
    if (req == null) throw StateError('request_not_ready');
    final res = await http.get(req.$1, headers: req.$2);
    FirebaseAuthHeaderProvider.logDebugResponse('BackendUserClient GET $path', res.statusCode, res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('http_${res.statusCode}');
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw StateError('invalid_json_response');
  }

  Future<Map<String, dynamic>?> _authedPatch(String path, Map<String, dynamic> body) async {
    final req = await _request(path);
    if (req == null) throw StateError('request_not_ready');
    final headers = <String, String>{...req.$2, 'Content-Type': 'application/json'};
    final res = await http.patch(req.$1, headers: headers, body: jsonEncode(body));
    FirebaseAuthHeaderProvider.logDebugResponse('BackendUserClient PATCH $path', res.statusCode, res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('http_${res.statusCode}');
    if (res.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<(Uri, Map<String, String>)?> _request(String path) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) throw StateError('backend_base_url_missing');
    final authHeaders = await FirebaseAuthHeaderProvider.requireAuthHeaders(reason: 'backend_user:$path');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    FirebaseAuthHeaderProvider.logRequestHeaders(method: 'REQUEST', uri: uri, headers: authHeaders);
    return (uri, authHeaders);
  }
}
