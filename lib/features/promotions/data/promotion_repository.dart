import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/contracts/feature_unit.dart';
import '../../../core/services/backend_orders_client.dart';
import '../../../core/services/firebase_auth_header_provider.dart';
import '../../store/domain/models.dart';
import '../domain/promotion_model.dart';

class PromotionRepository {
  PromotionRepository._();
  static final PromotionRepository instance = PromotionRepository._();

  Future<Map<String, String>> _headers() async {
    final auth = await FirebaseAuthHeaderProvider.requireAuthHeaders(reason: 'promotion_headers');
    return {...auth, 'Content-Type': 'application/json'};
  }

  Future<FeatureState<List<Promotion>>> fetchActivePromotions() async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for promotions.');
    final me = await BackendOrdersClient.instance.fetchAuthMe();
    final storeId = me?.storeId?.trim() ?? '';
    if (storeId.isEmpty) return FeatureState.success(const <Promotion>[]);

    final uri = Uri.parse('$base/stores/${Uri.encodeComponent(storeId)}/offers');
    http.Response res;
    try {
      res = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return FeatureState.failure('TIMEOUT');
    } on Object {
      return FeatureState.failure('UNEXPECTED_ERROR');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('Failed to load promotions (${res.statusCode})');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on Object {
      return FeatureState.failure('INVALID_JSON');
    }
    final items = decoded is Map && decoded['items'] is List ? decoded['items'] as List : const <dynamic>[];
    return FeatureState.success(
      items.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final discount = (m['discountPercent'] as num?)?.toDouble() ?? 0;
        return Promotion.fromMap(<String, dynamic>{
          'id': m['id']?.toString() ?? '',
          'name': m['title']?.toString() ?? '',
          'description': m['description']?.toString() ?? '',
          'type': 'percentage',
          'value': discount,
          'buyQuantity': 0,
          'getQuantity': 0,
          'getDiscount': 0,
          'applicableOn': 'store',
          'applicableIds': <String>[storeId],
          'minOrderAmount': 0,
          'maxDiscount': null,
          'startDate': DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
          'endDate': m['validUntil']?.toString() ??
              DateTime.fromMillisecondsSinceEpoch(253402300799000).toIso8601String(),
          'daysOfWeek': const <int>[1, 2, 3, 4, 5, 6, 7],
          'usageLimit': null,
          'usagePerUser': 999999,
          'usedCount': 0,
          'isActive': true,
          'isStackable': true,
          'createdAt': m['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          'createdBy': me?.userId ?? me?.firebaseUid ?? 'store_owner',
        });
      }).toList(),
    );
  }

  Stream<FeatureState<List<Promotion>>> getActivePromotions() =>
      Stream<FeatureState<List<Promotion>>>.fromFuture(fetchActivePromotions());
  Stream<FeatureState<List<Promotion>>> watchAllPromotions({int limit = 50}) =>
      Stream<FeatureState<List<Promotion>>>.fromFuture(fetchActivePromotions());

  Future<FeatureState<List<Promotion>>> getPromotionsForProduct(
    int productId,
    String storeId, {
    List<int>? categoryIds,
  }) async {
    final safeCategoryIds = categoryIds ?? List<int>.empty(growable: false);
    final activeState = await fetchActivePromotions();
    if (activeState is! FeatureSuccess<List<Promotion>>) {
      return switch (activeState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load promotions for product'),
      };
    }
    final all = activeState.data;
    return FeatureState.success(all.where((p) {
      if (p.applicableOn == 'all') return true;
      if (p.applicableOn == 'product') return p.applicableIds.contains(productId.toString());
      if (p.applicableOn == 'store') return p.applicableIds.contains(storeId);
      if (p.applicableOn == 'category') return safeCategoryIds.any((c) => p.applicableIds.contains(c.toString()));
      return false;
    }).toList());
  }

  Future<PromotionValidationResult> validatePromotion(Promotion p, List<CartItem> cart, String userId) async {
    final now = DateTime.now();
    if (!p.isActive) return const PromotionValidationResult(isValid: false, message: 'العرض غير نشط');
    if (now.isBefore(p.startDate) || now.isAfter(p.endDate)) {
      return const PromotionValidationResult(isValid: false, message: 'العرض خارج فترة الصلاحية');
    }
    return const PromotionValidationResult(isValid: true, message: 'ok', discountAmount: 0);
  }

  Future<FeatureState<PromotionsCalculationResult>> calculateDiscount(List<CartItem> cart, String userId) async {
    final activeState = await fetchActivePromotions();
    if (activeState is! FeatureSuccess<List<Promotion>>) {
      return switch (activeState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to calculate promotions'),
      };
    }
    final promos = activeState.data;
    if (promos.isEmpty || cart.isEmpty) {
      return FeatureState.success(
        PromotionsCalculationResult(appliedPromotions: <Promotion>[], discountAmount: 0, freeShipping: false),
      );
    }
    final byStore = <String, double>{};
    for (final item in cart) {
      byStore[item.storeId] = (byStore[item.storeId] ?? 0) + item.totalPrice;
    }
    double discountAmount = 0;
    final applied = <Promotion>[];
    for (final promotion in promos) {
      if (!promotion.isActive || promotion.type != 'percentage') continue;
      final targetStoreIds = promotion.applicableIds.toSet();
      final targetSubtotal = byStore.entries
          .where((e) => targetStoreIds.isEmpty || targetStoreIds.contains(e.key))
          .fold<double>(0, (sum, e) => sum + e.value);
      if (targetSubtotal <= 0) continue;
      final value = promotion.value.clamp(0, 100);
      final promoDiscount = targetSubtotal * (value / 100);
      if (promoDiscount <= 0) continue;
      discountAmount += promoDiscount;
      applied.add(promotion);
    }
    return FeatureState.success(
      PromotionsCalculationResult(appliedPromotions: applied, discountAmount: discountAmount, freeShipping: false),
    );
  }

  Future<FeatureState<FeatureUnit>> createPromotion(Promotion promotion) async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for promotions.');
    final me = await BackendOrdersClient.instance.fetchAuthMe();
    final storeId = me?.storeId?.trim() ?? '';
    if (storeId.isEmpty) return FeatureState.failure('INVALID_ID');
    final res = await http.post(
      Uri.parse('$base/stores/${Uri.encodeComponent(storeId)}/offers'),
      headers: await _headers(),
      body: jsonEncode(<String, dynamic>{
        'title': promotion.name,
        'description': promotion.description,
        'discountPercent': promotion.value,
        'validUntil': promotion.endDate.toUtc().toIso8601String(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('تعذر إنشاء العرض (${res.statusCode})');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updatePromotion(String id, Map<String, dynamic> patch) async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for promotions.');
    final res = await http.patch(
      Uri.parse('$base/offers/${Uri.encodeComponent(id.trim())}'),
      headers: await _headers(),
      body: jsonEncode(<String, dynamic>{
        if (patch['name'] != null) 'title': patch['name'],
        if (patch['description'] != null) 'description': patch['description'],
        if (patch['value'] != null) 'discountPercent': patch['value'],
        if (patch['endDate'] != null) 'validUntil': patch['endDate'],
        if (patch['isActive'] == false) 'validUntil': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('تعذر تحديث العرض (${res.statusCode})');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deletePromotion(String id) async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for promotions.');
    final res = await http.delete(
      Uri.parse('$base/offers/${Uri.encodeComponent(id.trim())}'),
      headers: await _headers(),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('تعذر حذف العرض (${res.statusCode})');
    }
    return FeatureState.success(FeatureUnit.value);
  }
}
