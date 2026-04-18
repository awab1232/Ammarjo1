import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_orders_config.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/logging/backend_fallback_logger.dart';
import '../../../core/utils/image_compress.dart';
import '../domain/maintenance_models.dart';

class ServiceRequestsRepository {
  // TODO-MIGRATE: remove Firebase Storage dependency after backend supports service-request image uploads.
  static const int _defaultAdminLimit = 30;
  static const int _defaultMyLimit = 20;

  ServiceRequestsRepository._();
  static final ServiceRequestsRepository instance = ServiceRequestsRepository._();

  static const bool _useBackendServiceRequestsDev = true;
  static bool get useBackendServiceRequests =>
      _useBackendServiceRequestsDev ||
      const bool.fromEnvironment('USE_BACKEND_SERVICE_REQUESTS', defaultValue: true);

  String? _nextCursor;
  String? get nextCursor => _nextCursor;

  String get _baseUrl => BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');

  Future<Map<String, String>> _authHeaders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('يرجى تسجيل الدخول أولاً');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) throw StateError('تعذر التحقق من هوية المستخدم');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  ServiceRequest _fromBackendMap(Map<String, dynamic> m) {
    DateTime parseDate(dynamic v) {
      if (v is String && v.trim().isNotEmpty) {
        return DateTime.tryParse(v)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    return ServiceRequest(
      id: (m['id']?.toString() ?? '').trim(),
      customerId: m['customerId']?.toString(),
      customerName: m['customerName']?.toString(),
      customerPhone: m['customerPhone']?.toString(),
      customerEmail: m['customerEmail']?.toString(),
      title: (m['title']?.toString().trim().isNotEmpty ?? false) ? m['title'].toString() : 'طلب خدمة',
      description: m['description']?.toString(),
      categoryId: m['categoryId']?.toString() ?? '',
      categoryName: m['categoryName']?.toString(),
      status: m['status']?.toString() ?? 'pending',
      createdAt: parseDate(m['createdAt']),
      updatedAt: m['updatedAt'] != null ? parseDate(m['updatedAt']) : null,
      assignedTechnicianId: m['assignedTechnicianId']?.toString() ?? m['technicianId']?.toString(),
      assignedTechnicianEmail: m['assignedTechnicianEmail']?.toString(),
      adminNote: m['adminNote']?.toString(),
      notes: m['notes']?.toString(),
      imageUrl: m['imageUrl']?.toString(),
      chatId: m['chatId']?.toString(),
    );
  }

  Future<Map<String, dynamic>> _httpGetJson(String path, {Map<String, String>? query}) async {
    if (!useBackendServiceRequests) throw StateError('Backend service requests disabled');
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('service_requests');
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'service_requests_http',
        reason: 'missing_backend_base_url',
      );
      throw StateError('Backend URL غير مضبوط');
    }
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'service_requests_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'service_requests_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      if (res.statusCode == 401) {
        throw StateError('انتهت الجلسة أو رمز الدخول غير صالح. سجّل الدخول مجدداً.');
      }
      if (res.statusCode == 403) {
        throw StateError('لا صلاحية لعرض طلبات الخدمة.');
      }
      throw StateError('فشل تحميل البيانات (${res.statusCode})');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw StateError('استجابة غير صالحة من الخادم');
  }

  Future<Map<String, dynamic>> _httpPostJson(String path, Map<String, dynamic> body) async {
    if (!useBackendServiceRequests) throw StateError('Backend service requests disabled');
    if (_baseUrl.isEmpty) {
      BackendOrdersConfig.warnIfBackendBaseUrlMissing('service_requests');
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'service_requests_http',
        reason: 'missing_backend_base_url',
      );
      throw StateError('Backend URL غير مضبوط');
    }
    final headers = await _authHeaders();
    final uri = Uri.parse('$_baseUrl$path');
    final res =
        await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'service_requests_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'service_requests_http',
        reason: 'http_${res.statusCode}',
        extra: {'path': path},
      );
      if (res.statusCode == 401) {
        throw StateError('انتهت الجلسة أو رمز الدخول غير صالح. سجّل الدخول مجدداً.');
      }
      if (res.statusCode == 403) {
        throw StateError('لا صلاحية لتنفيذ هذه العملية.');
      }
      throw StateError('فشل تنفيذ العملية (${res.statusCode})');
    }
    if (res.body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  Future<FeatureState<List<ServiceRequest>>> getServiceRequests({
    String? customerId,
    String? technicianId,
    String? status,
    int limit = 20,
    String? cursor,
  }) async {
    final q = <String, String>{
      'limit': '$limit',
      if (customerId != null && customerId.trim().isNotEmpty) 'customerId': customerId.trim(),
      if (technicianId != null && technicianId.trim().isNotEmpty) 'technicianId': technicianId.trim(),
      if (status != null && status.trim().isNotEmpty && status.trim() != 'all') 'status': status.trim(),
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
    };
    try {
      final res = await _httpGetJson('/service-requests', query: q);
      _nextCursor = res['nextCursor']?.toString();
      final items = (res['items'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((x) => _fromBackendMap(Map<String, dynamic>.from(x)))
          .toList();
      return FeatureState.success(items);
    } on Object {
      return FeatureState.failure('Failed to load service requests.');
    }
  }

  Future<ServiceRequest> getById(String id) async {
    final data = await _httpGetJson('/service-requests/${Uri.encodeComponent(id)}');
    return _fromBackendMap(data);
  }

  Future<String> createServiceRequestWithImage({
    required String technicianId,
    required String title,
    required String categoryId,
    required String customerEmail,
    required String description,
    required String technicianEmail,
    Uint8List? imageBytes,
    String? notes,
  }) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) throw StateError('يجب تسجيل الدخول أولاً');

    Reference? uploadedRef;
    String? imageUrl;
    try {
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final compressed = await compressImageBytes(imageBytes, quality: 72, minWidth: 1000);
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${current.uid}.jpg';
        uploadedRef = FirebaseStorage.instance.ref().child('service_requests/$fileName');
        await uploadedRef.putData(compressed, SettableMetadata(contentType: 'image/jpeg'));
        imageUrl = await uploadedRef.getDownloadURL();
      }

      final conversationId = 'conv_${DateTime.now().millisecondsSinceEpoch}_${current.uid}';
      final created = await _httpPostJson('/service-requests', {
        'conversationId': conversationId,
        'description': description,
        'imageUrl': imageUrl,
        'title': title,
        'categoryId': categoryId,
        'notes': notes ?? '',
      });
      final id = (created['id']?.toString() ?? '').trim();
      if (id.isEmpty) throw StateError('تعذر إنشاء طلب الخدمة');
      return id;
    } on Object {
      if (uploadedRef != null) {
        try {
          await uploadedRef.delete();
        } on Object {
          // Ignore cleanup failures for uploaded temp files.
        }
      }
      rethrow;
    }
  }

  Future<void> createRequest({
    required String title,
    required String categoryId,
    required String customerEmail,
    required String description,
    required String technicianEmail,
    String? notes,
  }) async {
    await createServiceRequestWithImage(
      technicianId: '',
      title: title,
      categoryId: categoryId,
      customerEmail: customerEmail,
      description: description,
      technicianEmail: technicianEmail,
      notes: notes,
    );
  }

  Future<void> updateServiceRequest({
    required String requestId,
    String? assignedTechnicianId,
    String? assignedTechnicianEmail,
    String? status,
    String? adminNote,
  }) async {
    final id = requestId.trim();
    final st = status?.trim().toLowerCase();
    if (st == 'assigned' && assignedTechnicianId != null && assignedTechnicianId.trim().isNotEmpty) {
      await _httpPostJson('/service-requests/$id/assign', {'technicianId': assignedTechnicianId.trim()});
      return;
    }
    if (st == 'in_progress' || st == 'start') {
      await _httpPostJson('/service-requests/$id/start', <String, dynamic>{});
      return;
    }
    if (st == 'completed' || st == 'complete') {
      await _httpPostJson('/service-requests/$id/complete', <String, dynamic>{});
      return;
    }
    if (st == 'cancelled' || st == 'cancel') {
      await _httpPostJson('/service-requests/$id/cancel', <String, dynamic>{});
      return;
    }
  }

  Future<void> attachChatIdToRequest(String requestId, String chatId) async {
    if (requestId.isEmpty || chatId.isEmpty) return;
    await _httpPostJson('/service-requests/$requestId/attach-chat', {
      'chatId': chatId,
    });
  }

  Future<FeatureState<double>> sumEarningsForTechnician(String technicianEmail) async {
    if (technicianEmail.isEmpty) {
      return FeatureState.failure('Technician email is required.');
    }
    try {
      final res = await _httpGetJson(
        '/service-requests/earnings',
        query: {'technicianEmail': technicianEmail},
      );
      final totalRaw = res['total'];
      final total = (totalRaw as num?)?.toDouble();
      if (total == null) {
        return FeatureState.failure('INVALID_NUMERIC_DATA');
      }
      return FeatureState.success(total);
    } on Object {
      return FeatureState.failure('Failed to load technician earnings.');
    }
  }

  /// [cursor] is the opaque `nextCursor` from the previous page; omit or pass null for the first page.
  Future<FeatureState<({
    List<ServiceRequest> items,
    String? nextCursor,
    bool hasMore,
  })>> getMyServiceRequestsPage({
    required String customerId,
    required int limit,
    String? cursor,
  }) async {
    final itemsState = await getServiceRequests(
      customerId: customerId,
      limit: limit,
      cursor: cursor,
    );
    if (itemsState is! FeatureSuccess<List<ServiceRequest>>) {
      return switch (itemsState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
      };
    }
    final next = _nextCursor;
    return FeatureState.success((
      items: itemsState.data,
      nextCursor: next,
      hasMore: next != null && next.isNotEmpty,
    ));
  }

  /// Admin: unscoped filters allowed by backend when the caller has admin/system role.
  Future<FeatureState<({
    List<ServiceRequest> items,
    String? nextCursor,
    bool hasMore,
  })>> getServiceRequestsPage({
    required int limit,
    String? cursor,
    String? statusFilter,
    String? technicianId,
  }) async {
    final itemsState = await getServiceRequests(
      technicianId: technicianId,
      status: statusFilter,
      limit: limit,
      cursor: cursor,
    );
    if (itemsState is! FeatureSuccess<List<ServiceRequest>>) {
      return switch (itemsState) {
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
      };
    }
    final next = _nextCursor;
    return FeatureState.success((
      items: itemsState.data,
      nextCursor: next,
      hasMore: next != null && next.isNotEmpty,
    ));
  }

  Future<FeatureState<List<ServiceRequest>>> fetchServiceRequestsPageAfter({
    required String cursor,
    String? statusFilter,
    String? technicianId,
    int limit = _defaultAdminLimit,
  }) async {
    final pageState = await getServiceRequestsPage(
      limit: limit,
      cursor: cursor,
      statusFilter: statusFilter,
      technicianId: technicianId,
    );
    return switch (pageState) {
      FeatureSuccess(:final data) => FeatureState.success(data.items),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
      _ => FeatureState.failure('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
    };
  }

  Future<FeatureState<List<ServiceRequest>>> fetchMyServiceRequestsPageAfter({
    required String customerId,
    required String cursor,
    int limit = _defaultMyLimit,
  }) async {
    final pageState = await getMyServiceRequestsPage(
      customerId: customerId,
      limit: limit,
      cursor: cursor,
    );
    return switch (pageState) {
      FeatureSuccess(:final data) => FeatureState.success(data.items),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
      _ => FeatureState.failure('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
    };
  }

  /// Single snapshot from `GET /service-requests` (admin scope; requires elevated role on backend).
  Stream<FeatureState<List<ServiceRequest>>> watchPool() =>
      Stream<FeatureState<List<ServiceRequest>>>.fromFuture(getServiceRequests(limit: _defaultAdminLimit));

  /// Backend: `technicianId` must match the signed-in user (uid or email per server rules).
  Stream<FeatureState<List<ServiceRequest>>> watchForTechnician(String technicianId) =>
      Stream<FeatureState<List<ServiceRequest>>>.fromFuture(
        getServiceRequests(technicianId: technicianId.trim(), limit: _defaultAdminLimit),
      );

  Stream<FeatureState<List<ServiceRequest>>> watchMyServiceRequests(String customerId, {int limit = _defaultMyLimit}) =>
      Stream<FeatureState<List<ServiceRequest>>>.fromFuture(
        getServiceRequests(customerId: customerId.trim(), limit: limit),
      );

  Stream<FeatureState<List<ServiceRequest>>> watchServiceRequestsForAdmin({
    String? statusFilter,
    String? technicianId,
    int limit = _defaultAdminLimit,
  }) =>
      Stream<FeatureState<List<ServiceRequest>>>.fromFuture(
        getServiceRequests(
          status: statusFilter,
          technicianId: technicianId,
          limit: limit,
        ),
      );

  Future<FeatureState<TechnicianProfile>> getTechnician(String technicianId) async {
    if (technicianId.isEmpty) return FeatureState.failure('NULL_RESPONSE');
    return FeatureState.failure('DATA_NOT_FOUND');
  }
}


