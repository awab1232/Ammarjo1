import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';
import '../contracts/feature_state.dart';
import 'firebase_auth_header_provider.dart';

final class BackendUserClient {
  BackendUserClient._();
  static final BackendUserClient instance = BackendUserClient._();

  Future<Map<String, dynamic>?> fetchMe() async {
    return _authedGet('/auth/me');
  }

  Future<Map<String, dynamic>?> fetchUserById(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) throw StateError('NULL_RESPONSE');
    return _authedGet('/users/${Uri.encodeComponent(id)}');
  }

  Future<bool> patchUser(String uid, Map<String, dynamic> fields) async {
    final id = uid.trim();
    if (id.isEmpty || fields.isEmpty) return false;
    final body = await _authedPatch('/users/${Uri.encodeComponent(id)}', fields);
    return body != null;
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchTechSpecialties() async {
    final body = await _authedGet('/tech-specialties');
    final items = body?['items'];
    if (items is! List) return FeatureState.failure('Invalid specialties payload.');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchUserFavorites(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return FeatureState.failure('User id is required.');
    final body = await _authedGet('/users/${Uri.encodeComponent(id)}/favorites');
    final items = body?['items'];
    if (items is! List) return FeatureState.failure('Invalid favorites payload.');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<bool> putUserFavorite(String uid, Map<String, dynamic> payload) async {
    final id = uid.trim();
    final pid = payload['productId']?.toString().trim() ?? '';
    if (id.isEmpty || pid.isEmpty) return false;
    final body = await _authedPatch('/users/${Uri.encodeComponent(id)}/favorites/${Uri.encodeComponent(pid)}', payload);
    return body != null;
  }

  Future<bool> deleteUserFavorite(String uid, String productId) async {
    final id = uid.trim();
    final pid = productId.trim();
    if (id.isEmpty || pid.isEmpty) return false;
    final ok = await _authedDelete('/users/${Uri.encodeComponent(id)}/favorites/${Uri.encodeComponent(pid)}');
    return ok;
  }

  Future<Map<String, dynamic>?> _authedGet(String path) async {
    final req = await _request(path);
    if (req == null) throw StateError('NULL_RESPONSE');
    final res = await http.get(req.$1, headers: req.$2);
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('NULL_RESPONSE');
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw StateError('NULL_RESPONSE');
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

  Future<bool> _authedDelete(String path) async {
    final req = await _request(path);
    if (req == null) return false;
    final res = await http.delete(req.$1, headers: req.$2);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<(Uri, Map<String, String>)?> _request(String path) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    if (base.isEmpty) throw StateError('NULL_RESPONSE');
    final authHeaders = await FirebaseAuthHeaderProvider.requireAuthHeaders(reason: 'backend_user:$path');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    FirebaseAuthHeaderProvider.logRequestHeaders(method: 'REQUEST', uri: uri, headers: authHeaders);
    return (uri, authHeaders);
  }
}
