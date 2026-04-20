import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';
import '../contracts/feature_state.dart';

final class BackendUserClient {
  BackendUserClient._();
  static final BackendUserClient instance = BackendUserClient._();

  Future<Map<String, dynamic>?> fetchMe() async {
    return _authedGet('/auth/me');
  }

  Future<Map<String, dynamic>?> fetchUserById(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) throw StateError('NULL_RESPONSE');
    final me = await fetchMe();
    if (me == null) return null;
    final firebaseUid = (me['firebaseUid'] ?? '').toString().trim();
    final internalId = (me['id'] ?? '').toString().trim();
    final email = (me['email'] ?? '').toString().trim();
    if (id == firebaseUid || id == internalId || (email.isNotEmpty && id == email)) {
      return me;
    }
    // `/users/:id` is not exposed in the backend; avoid hitting a non-existent endpoint.
    return null;
  }

  Future<bool> patchUser(String uid, Map<String, dynamic> fields) async {
    final id = uid.trim();
    if (id.isEmpty || fields.isEmpty) return false;
    // Hotfix: disable broken `/users/:id` calls until a public profile endpoint is exposed.
    debugPrint('[BackendUserClient] patchUser skipped: /users/:id is not wired. fields=${fields.keys.toList()}');
    return false;
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchTechSpecialties() async {
    debugPrint('[BackendUserClient] fetchTechSpecialties skipped: endpoint not publicly wired.');
    return FeatureState.success(const <Map<String, dynamic>>[]);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchUserFavorites(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return FeatureState.failure('User id is required.');
    debugPrint('[BackendUserClient] fetchUserFavorites skipped: /users/:id/favorites is not wired.');
    return FeatureState.success(const <Map<String, dynamic>>[]);
  }

  Future<bool> putUserFavorite(String uid, Map<String, dynamic> payload) async {
    final id = uid.trim();
    final pid = payload['productId']?.toString().trim() ?? '';
    if (id.isEmpty || pid.isEmpty) return false;
    debugPrint('[BackendUserClient] putUserFavorite skipped: /users/:id/favorites is not wired.');
    return false;
  }

  Future<bool> deleteUserFavorite(String uid, String productId) async {
    final id = uid.trim();
    final pid = productId.trim();
    if (id.isEmpty || pid.isEmpty) return false;
    debugPrint('[BackendUserClient] deleteUserFavorite skipped: /users/:id/favorites is not wired.');
    return false;
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

  Future<(Uri, Map<String, String>)?> _request(String path) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (base.isEmpty || user == null) throw StateError('NULL_RESPONSE');
    final token = (await user.getIdToken()) ?? '';
    if (token.isEmpty) throw StateError('NULL_RESPONSE');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path');
    return (uri, <String, String>{'Authorization': 'Bearer $token'});
  }
}
