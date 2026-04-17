import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';
import '../contracts/feature_state.dart';

final class BackendTenderClient {
  BackendTenderClient._();
  static final BackendTenderClient instance = BackendTenderClient._();

  Future<FeatureState<List<Map<String, dynamic>>>> fetchMyTenders() async {
    final body = await _authedGet('/tenders/mine');
    final items = body?['items'];
    if (items is! List) return FeatureState.failure('Invalid tenders payload.');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  /// Open feed for store owners: tenders whose `storeTypeId` (or `storeTypeKey`)
  /// matches the store's own type. City is an optional narrowing filter.
  Future<FeatureState<List<Map<String, dynamic>>>> fetchOpenTendersForStore({
    String? storeTypeId,
    String? storeTypeKey,
    String? city,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (storeTypeId != null && storeTypeId.trim().isNotEmpty) 'storeTypeId': storeTypeId.trim(),
      if (storeTypeKey != null && storeTypeKey.trim().isNotEmpty) 'storeTypeKey': storeTypeKey.trim(),
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
    };
    final body = await _authedGet('/tenders/open', query: query);
    final items = body?['items'];
    if (items is! List) return FeatureState.failure('Invalid tenders payload.');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  /// Lifecycle mutation: PATCH `/tenders/:id` with `{status: closed|cancelled}`.
  Future<Map<String, dynamic>?> patchTenderStatus(String tenderId, {required String status}) {
    return _authedPatch(
      '/tenders/${Uri.encodeComponent(tenderId)}',
      <String, dynamic>{'status': status},
    );
  }

  /// Hard delete for a tender (customer owner only, enforced server-side).
  Future<Map<String, dynamic>?> deleteTender(String tenderId) async {
    final req = await _request('/tenders/${Uri.encodeComponent(tenderId)}');
    if (req == null) throw StateError('NULL_RESPONSE');
    final res = await http.delete(req.$1, headers: req.$2);
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('NULL_RESPONSE');
    if (res.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> fetchTender(String tenderId) async {
    final id = tenderId.trim();
    if (id.isEmpty) throw StateError('NULL_RESPONSE');
    return _authedGet('/tenders/${Uri.encodeComponent(id)}');
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchTenderOffers(String tenderId) async {
    final id = tenderId.trim();
    if (id.isEmpty) return FeatureState.failure('Tender id is required.');
    final body = await _authedGet('/tenders/${Uri.encodeComponent(id)}/offers');
    final items = body?['items'];
    if (items is! List) return FeatureState.failure('Invalid tender offers payload.');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<Map<String, dynamic>?> createTender({
    required String category,
    required String description,
    required String city,
    required String userName,
    String? storeTypeId,
    String? storeTypeKey,
    String? storeTypeName,
    Uint8List? imageBytes,
  }) async {
    return _authedPost('/tenders', <String, dynamic>{
      'category': category,
      'description': description,
      'city': city,
      'userName': userName,
      if (storeTypeId != null && storeTypeId.trim().isNotEmpty) 'storeTypeId': storeTypeId.trim(),
      if (storeTypeKey != null && storeTypeKey.trim().isNotEmpty) 'storeTypeKey': storeTypeKey.trim(),
      if (storeTypeName != null && storeTypeName.trim().isNotEmpty) 'storeTypeName': storeTypeName.trim(),
      if (imageBytes != null) 'imageBase64': base64Encode(imageBytes),
    });
  }

  Future<Map<String, dynamic>?> submitOffer({
    required String tenderId,
    required String storeId,
    required String storeName,
    required double price,
    required String note,
  }) {
    return _authedPost('/tenders/${Uri.encodeComponent(tenderId)}/offers', <String, dynamic>{
      'storeId': storeId,
      'storeName': storeName,
      'price': price,
      'note': note,
    });
  }

  Future<Map<String, dynamic>?> acceptOffer({
    required String tenderId,
    required String offerId,
  }) {
    return _authedPatch(
      '/tenders/${Uri.encodeComponent(tenderId)}/offers/${Uri.encodeComponent(offerId)}',
      <String, dynamic>{'status': 'accepted'},
    );
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreCommissions(
    String storeId, {
    int limit = 20,
    String? cursor,
  }) async {
    final id = storeId.trim();
    if (id.isEmpty) return FeatureState.failure('Store id is required.');
    final body = await _authedGet(
      '/stores/${Uri.encodeComponent(id)}/commissions',
      query: <String, String>{
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    final items = body?['items'];
    if (items is! List) return FeatureState.failure('Invalid commissions payload.');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
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

  Future<Map<String, dynamic>?> _authedPost(String path, Map<String, dynamic> body) async {
    final req = await _request(path);
    if (req == null) throw StateError('NULL_RESPONSE');
    final headers = <String, String>{...req.$2, 'Content-Type': 'application/json'};
    final res = await http.post(req.$1, headers: headers, body: jsonEncode(body));
    if (res.statusCode < 200 || res.statusCode >= 300) throw StateError('NULL_RESPONSE');
    if (res.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
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

  Future<(Uri, Map<String, String>)?> _request(String path, {Map<String, String>? query}) async {
    final base = BackendOrdersConfig.baseUrl.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (base.isEmpty || user == null) throw StateError('NULL_RESPONSE');
    final token = (await user.getIdToken()) ?? '';
    if (token.isEmpty) throw StateError('NULL_RESPONSE');
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/$'), '')}$path').replace(queryParameters: query);
    return (uri, <String, String>{'Authorization': 'Bearer $token'});
  }
}
