import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/logging/backend_fallback_logger.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/contracts/feature_unit.dart';
import '../domain/review_model.dart';

class ReviewsRepository {
  ReviewsRepository._();
  static final ReviewsRepository instance = ReviewsRepository._();

  static const bool _useBackendRatingsDev = true;
  static bool get useBackendRatings =>
      _useBackendRatingsDev || const bool.fromEnvironment('USE_BACKEND_RATINGS', defaultValue: true);
  String? _nextCursor;
  String? get nextCursor => _nextCursor;

  String get _baseUrl => BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');

  String _normalizedTargetType(String targetType) {
    final t = targetType.trim().toLowerCase();
    if (t == 'wholesaler') return 'home_store';
    return t;
  }

  Future<FeatureState<Map<String, String>>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return FeatureState.failure('Ã™Å Ã˜Â±Ã˜Â¬Ã™â€° Ã˜ÂªÃ˜Â³Ã˜Â¬Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â¯Ã˜Â®Ã™Ë†Ã™â€ž Ã˜Â£Ã™Ë†Ã™â€žÃ˜Â§Ã™â€¹');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) return FeatureState.failure('Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã™â€¡Ã™Ë†Ã™Å Ã˜Â© Ã˜Â§Ã™â€žÃ™â€¦Ã˜Â³Ã˜ÂªÃ˜Â®Ã˜Â¯Ã™â€¦');
    return FeatureState.success({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
  }

  Future<FeatureState<dynamic>> _httpGetJson(String path, {Map<String, String>? query}) async {
    if (!useBackendRatings) return FeatureState.failure('Backend ratings disabled');
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('ratings_http');
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'ratings_http',
        reason: 'missing_backend_base_url',
      );
      return FeatureState.failure('Backend URL Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â¶Ã˜Â¨Ã™Ë†Ã˜Â·');
    }
    final headersState = await _authHeaders();
    if (headersState is! FeatureSuccess<Map<String, String>>) {
      return switch (headersState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Authorization failed'),
      };
    }
    final headers = headersState.data;
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'ratings_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'ratings_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      return FeatureState.failure('Ã™ÂÃ˜Â´Ã™â€ž Ã˜ÂªÃ˜Â­Ã™â€¦Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€šÃ™Å Ã™Å Ã™â€¦Ã˜Â§Ã˜Âª (${res.statusCode})');
    }
    return FeatureState.success(jsonDecode(res.body));
  }

  Future<FeatureState<Map<String, dynamic>>> _httpPostJson(String path, Map<String, dynamic> body) async {
    if (!useBackendRatings) return FeatureState.failure('Backend ratings disabled');
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('ratings_http');
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'ratings_http',
        reason: 'missing_backend_base_url',
      );
      return FeatureState.failure('Backend URL Ã˜ÂºÃ™Å Ã˜Â± Ã™â€¦Ã˜Â¶Ã˜Â¨Ã™Ë†Ã˜Â·');
    }
    final headersState = await _authHeaders();
    if (headersState is! FeatureSuccess<Map<String, String>>) {
      return switch (headersState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Authorization failed'),
      };
    }
    final headers = headersState.data;
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http
        .post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'ratings_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'ratings_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      return FeatureState.failure('Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜Â¥Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ™â€šÃ™Å Ã™Å Ã™â€¦ (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return FeatureState.success(decoded);
    if (decoded is Map) return FeatureState.success(Map<String, dynamic>.from(decoded));
    return FeatureState.failure('Invalid backend response payload');
  }

  Future<FeatureState<Map<String, dynamic>>> _httpPatchJson(String path, Map<String, dynamic> body) async {
    if (!useBackendRatings) return FeatureState.failure('Backend ratings disabled');
    if (_baseUrl.isEmpty) return FeatureState.failure('Backend URL غير مضبوط');
    final headersState = await _authHeaders();
    if (headersState is! FeatureSuccess<Map<String, String>>) return FeatureState.failure('Authorization failed');
    final uri = Uri.parse('$_baseUrl$path');
    final res = await http
        .patch(uri, headers: headersState.data, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return FeatureState.failure('REQUEST_FAILED');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return FeatureState.success(decoded);
    if (decoded is Map) return FeatureState.success(Map<String, dynamic>.from(decoded));
    return FeatureState.success(<String, dynamic>{'ok': true});
  }

  Future<FeatureState<List<ReviewModel>>> getReviews({
    required String targetId,
    required String targetType,
    int limit = 30,
    String? cursor,
  }) async {
    final normalizedType = _normalizedTargetType(targetType);
    final responseState = await _httpGetJson(
      '/ratings/${Uri.encodeComponent(normalizedType)}/${Uri.encodeComponent(targetId)}',
      query: <String, String>{
        'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    if (responseState is! FeatureSuccess<dynamic>) {
      return switch (responseState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load reviews'),
      };
    }
    final response = responseState.data;
    if (response is List) {
      _nextCursor = null;
      final list = response
          .whereType<Map>()
          .map((x) => ReviewModel.fromBackendMap(Map<String, dynamic>.from(x)))
          .toList();
      return FeatureState.success(list);
    }
    if (response is Map) {
      final map = Map<String, dynamic>.from(response);
      _nextCursor = map['nextCursor']?.toString();
      final rows = (map['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((x) => ReviewModel.fromBackendMap(Map<String, dynamic>.from(x)))
          .toList();
      final ids = <String>{};
      return FeatureState.success(rows.where((r) => ids.add(r.id)).toList());
    }
    return FeatureState.failure('Invalid reviews payload from backend');
  }

  Future<FeatureState<RatingAggregate>> getAggregate({
    required String targetId,
    required String targetType,
  }) async {
    final normalizedType = _normalizedTargetType(targetType);
    final responseState = await _httpGetJson(
      '/ratings/${Uri.encodeComponent(normalizedType)}/${Uri.encodeComponent(targetId)}/aggregate',
    );
    if (responseState is! FeatureSuccess<dynamic>) {
      return switch (responseState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load aggregate'),
      };
    }
    final response = responseState.data;
    if (response is Map<String, dynamic>) {
      return FeatureState.success(RatingAggregate.fromBackendMap(response));
    }
    if (response is Map) {
      return FeatureState.success(RatingAggregate.fromBackendMap(Map<String, dynamic>.from(response)));
    }
    return FeatureState.failure('Invalid aggregate payload from backend');
  }

  /// Ã™Å Ã˜ÂªÃ˜Â­Ã™â€šÃ™â€š Ã™â€¦Ã™â€  Ã™Ë†Ã˜Â¬Ã™Ë†Ã˜Â¯ Ã™â€¦Ã™â€ Ã˜ÂªÃ˜Â¬ Ã™ÂÃ™Å  `orders/{id}.items` Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨Ã˜Â§Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â¹Ã™â€¦Ã™Å Ã™â€ž (Woo `productId`).
  Future<bool> hasCustomerPurchasedProductWooId({
    required String customerUid,
    required int productWooId,
  }) async {
    if (customerUid.trim().isEmpty) return false;
    try {
      // Legacy read-only behavior: purchase gating is no longer enforced via Firestore.
      // deprecated - migrated to Postgres ratings_reviews
      return true;
    } on Object {
      debugPrint('[ReviewsRepository] hasCustomerPurchasedProductWooId: unexpected error\n$StackTrace.current');
    }
    return true;
  }

  Future<FeatureState<FeatureUnit>> createReview({
    required String targetId,
    required String targetType,
    required String userId,
    required String userName,
    required double rating,
    required String comment,
    String? orderId,
    double? deliverySpeed,
    double? productQuality,
    List<String> images = const <String>[],
  }) async {
    final postState = await _httpPostJson('/ratings', <String, dynamic>{
      'targetType': _normalizedTargetType(targetType),
      'targetId': targetId.trim(),
      'rating': rating.clamp(1, 5).round(),
      'reviewText': comment.trim(),
      if (orderId != null && orderId.trim().isNotEmpty) 'orderId': orderId.trim(),
      if (deliverySpeed != null) 'deliverySpeed': deliverySpeed.clamp(1, 5).round(),
      if (productQuality != null) 'productQuality': productQuality.clamp(1, 5).round(),
    });
    return switch (postState) {
      FeatureSuccess() => FeatureState.success(FeatureUnit.value),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
      _ => FeatureState.failure('Failed to create review'),
    };
  }

  Future<FeatureState<FeatureUnit>> upsertReview({
    required String targetId,
    required String targetType,
    required String userId,
    required String userName,
    required double rating,
    required String comment,
    String? orderId,
    double? deliverySpeed,
    double? productQuality,
    List<String> images = const <String>[],
  }) {
    return createReview(
      targetId: targetId,
      targetType: targetType,
      userId: userId,
      userName: userName,
      rating: rating,
      comment: comment,
      orderId: orderId,
      deliverySpeed: deliverySpeed,
      productQuality: productQuality,
      images: images,
    );
  }

  Stream<FeatureState<List<ReviewModel>>> watchForTarget({
    required String targetId,
    required String targetType,
  }) async* {
    final state = await getReviews(targetId: targetId, targetType: targetType);
    if (state is FeatureFailure<List<ReviewModel>>) {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'ratings_watch',
        reason: 'feature_failure',
        extra: {'targetId': targetId, 'targetType': targetType, 'error': state.message},
      );
    }
    yield state;
  }

  Stream<FeatureState<List<ReviewModel>>> watchByTargetTypeForAdmin({
    required String targetType,
    int limit = 50,
    int offset = 0,
  }) async* {
    final responseState = await _httpGetJson('/admin/rest/ratings', query: <String, String>{
      'targetType': targetType,
      'limit': '$limit',
      'offset': '$offset',
    });
    if (responseState is! FeatureSuccess<dynamic>) {
      yield switch (responseState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load admin reviews'),
      };
      return;
    }
    final raw = responseState.data;
    if (raw is! Map) {
      yield FeatureState.failure('Invalid admin reviews payload');
      return;
    }
    final items = ((Map<String, dynamic>.from(raw))['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((x) => ReviewModel.fromBackendMap(Map<String, dynamic>.from(x)))
        .toList();
    yield FeatureState.success(items);
  }

  Future<FeatureState<FeatureUnit>> deleteReview(String reviewId) async {
    if (reviewId.trim().isEmpty) return FeatureState.failure('INVALID_ID');
    final tokenState = await _authHeaders();
    if (tokenState is! FeatureSuccess<Map<String, String>>) {
      return FeatureState.failure('Authorization failed');
    }
    final uri = Uri.parse('$_baseUrl/admin/rest/ratings/${Uri.encodeComponent(reviewId.trim())}');
    try {
      final res = await http.delete(uri, headers: tokenState.data).timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) return FeatureState.failure('REQUEST_FAILED');
      return FeatureState.success(FeatureUnit.value);
    } on Object {
      return FeatureState.failure('REQUEST_FAILED');
    }
  }

  Future<FeatureState<FeatureUnit>> addReply({
    required String reviewId,
    required String authorId,
    required String authorName,
    required String text,
  }) async {
    if (reviewId.trim().isEmpty) return FeatureState.failure('INVALID_ID');
    final state = await _httpPatchJson(
      '/admin/rest/ratings/${Uri.encodeComponent(reviewId.trim())}',
      <String, dynamic>{'reviewText': text.trim()},
    );
    return switch (state) {
      FeatureSuccess() => FeatureState.success(FeatureUnit.value),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
      _ => FeatureState.failure('REQUEST_FAILED'),
    };
  }
}

