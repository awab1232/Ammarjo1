import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/contracts/feature_unit.dart';
import '../../store/domain/models.dart';
import '../domain/coupon_model.dart';

class CouponRepository {
  CouponRepository._();
  static final CouponRepository instance = CouponRepository._();

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('غير مسجّل');
    final token = (await user.getIdToken()) ?? '';
    if (token.isEmpty) throw StateError('تعذر التحقق من الهوية');
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  Future<FeatureState<List<Coupon>>> getCouponsPage({int limit = 30, Object? startAfter}) async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for coupons.');
    final uri = Uri.parse('$base/admin/rest/coupons').replace(queryParameters: {'limit': '$limit'});
    http.Response res;
    try {
      res = await http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return FeatureState.failure('TIMEOUT');
    } on Object {
      return FeatureState.failure('UNEXPECTED_ERROR');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('Failed to load coupons (${res.statusCode})');
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } on Object {
      return FeatureState.failure('INVALID_JSON');
    }
    final items = decoded is List
        ? decoded
        : (decoded is Map && decoded['items'] is List ? decoded['items'] as List : const <dynamic>[]);
    return FeatureState.success(
      items.whereType<Map>().map((e) => Coupon.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }

  Future<FeatureState<Coupon>> getCoupon(String code) async {
    final allState = await getCouponsPage(limit: 200);
    if (allState is! FeatureSuccess<List<Coupon>>) {
      return switch (allState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to resolve coupon'),
      };
    }
    final all = allState.data;
    final c = code.trim().toUpperCase();
    for (final coupon in all) {
      if (coupon.code == c) return FeatureState.success(coupon);
    }
    return FeatureState.failure('الكود غير موجود');
  }

  Future<FeatureState<CouponValidationResult>> validateCoupon(String code, String userId, List<CartItem> cart) async {
    final couponState = await getCoupon(code);
    if (couponState is! FeatureSuccess<Coupon>) {
      return FeatureState.failure(
        couponState is FeatureFailure<Coupon> ? couponState.message : 'الكود غير موجود',
      );
    }
    final c = couponState.data;
    final orderAmount = cart.fold<double>(0, (s, e) => s + e.totalPrice);
    final productIds = cart.map((e) => e.product.id).toList();
    final storeIds = cart.map((e) => e.storeId).toSet().toList();
    final valid = c.isValid(
      userId: userId,
      orderAmount: orderAmount,
      productIds: productIds,
      storeIds: storeIds,
      userUsedCount: 0,
    );
    if (!valid) {
      return FeatureState.failure('الكود لا ينطبق على السلة الحالية');
    }
    final discount = c.calculateDiscount(orderAmount: orderAmount);
    if (discount <= 0) return FeatureState.failure('لا يوجد خصم قابل للتطبيق');
    return FeatureState.success(
      CouponValidationResult(isValid: true, message: 'تم تطبيق الكوبون', coupon: c, discountAmount: discount),
    );
  }

  Stream<FeatureState<List<Coupon>>> watchCoupons({int limit = 30}) =>
      Stream<FeatureState<List<Coupon>>>.fromFuture(getCouponsPage(limit: limit));

  Future<FeatureState<int>> getCouponsCount() async {
    final state = await getCouponsPage(limit: 200);
    return switch (state) {
      FeatureSuccess(:final data) => FeatureState.success(data.length),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
      _ => FeatureState.failure('Failed to count coupons'),
    };
  }

  Future<double> getTotalDiscountGiven() async => 0;
  Future<double> totalDiscountProvided({String? couponCode}) async => 0;
  Future<Map<DateTime, int>> getDailyUsage(String couponCode, {int days = 30}) async => <DateTime, int>{};
  Future<FeatureState<List<CouponUsage>>> getCouponUsage(String couponCode, {int limit = 100}) async =>
      FeatureState.failure('Coupon usage endpoint is not wired.');

  Future<FeatureState<FeatureUnit>> createCoupon(Coupon coupon) async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for coupons.');
    final res = await http.post(
      Uri.parse('$base/admin/rest/coupons'),
      headers: await _headers(),
      body: jsonEncode(coupon.toMap()),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('تعذر إنشاء الكوبون (${res.statusCode})');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateCoupon(String id, Map<String, dynamic> data) async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for coupons.');
    final res = await http.patch(
      Uri.parse('$base/admin/rest/coupons/${Uri.encodeComponent(id.trim())}'),
      headers: await _headers(),
      body: jsonEncode(data),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('تعذر تحديث الكوبون (${res.statusCode})');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteCoupon(String id) async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) return FeatureState.failure('Backend URL missing for coupons.');
    final res = await http.delete(
      Uri.parse('$base/admin/rest/coupons/${Uri.encodeComponent(id.trim())}'),
      headers: await _headers(),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('تعذر حذف الكوبون (${res.statusCode})');
    }
    return FeatureState.success(FeatureUnit.value);
  }
}
