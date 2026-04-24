import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/contracts/feature_state.dart';
import '../../../core/contracts/feature_unit.dart';
import '../../../core/session/backend_identity_controller.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/firebase/user_notifications_repository.dart';
import '../../../core/data/repositories/home_repository.dart';
import '../../stores/data/store_types_repository.dart';
import 'admin_overview_metrics.dart';
import 'backend_admin_client.dart';

/// Pending technician join row from PostgreSQL (`technician_join_requests`).
class TechnicianJoinRequest {
  TechnicianJoinRequest({
    required this.id,
    required this.email,
    required this.displayName,
    required this.specialties,
    required this.categoryId,
    required this.phone,
    required this.city,
    required this.cities,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final List<String> specialties;
  final String categoryId;
  final String phone;
  final String city;
  final List<String> cities;
  final String status;
  final DateTime createdAt;

  factory TechnicianJoinRequest.fromJson(Map<String, dynamic> j) {
    DateTime created = DateTime.now();
    final t = j['created_at'];
    if (t is String) {
      created = DateTime.tryParse(t) ?? created;
    }
    final specs = j['specialties'];
    final cityStr = j['city'] as String? ?? 'الأردن';
    final rawCities = j['cities'];
    final List<String> citiesList = rawCities is List
        ? rawCities.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    if (citiesList.isEmpty && cityStr.trim().isNotEmpty) {
      citiesList.add(cityStr.trim());
    }
    return TechnicianJoinRequest(
      id: j['id']?.toString() ?? '',
      email: j['email'] as String? ?? '',
      displayName: j['display_name'] as String? ?? 'فني',
      specialties: specs is List ? specs.map((e) => e.toString()).toList() : const <String>[],
      categoryId: j['category_id'] as String? ?? 'plumber',
      phone: j['phone'] as String? ?? '',
      city: cityStr,
      cities: citiesList.isEmpty ? <String>[cityStr] : citiesList,
      status: j['status'] as String? ?? 'pending',
      createdAt: created,
    );
  }
}

/// حالة رابط «لوحة التحكم» في الـ Drawer.
class FullAdminDrawerState {
  const FullAdminDrawerState({
    required this.showAdminLink,
    this.rawRoleFromFirestore,
    this.effectiveStaffRole,
  });

  final bool showAdminLink;
  final String? rawRoleFromFirestore;
  final String? effectiveStaffRole;
}

class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  void _invalidateStoreTaxonomyCaches() {
    StoreTypesRepository.instance.invalidate();
    HomeRepository.instance.invalidateAll();
  }

  static const Duration _adminCacheDuration = Duration(seconds: 30);

  String? _isAdminUserCacheUid;
  DateTime? _isAdminUserCacheAt;
  bool? _isAdminUserCacheValue;

  String? _shouldOpenCacheUid;
  DateTime? _shouldOpenCacheAt;
  bool? _shouldOpenCacheValue;

  StreamSubscription<void>? _userDocIdentitySub;
  StreamController<Map<String, dynamic>?>? _userDocController;

  bool _isAdminUserCacheHit(String uid) {
    return _isAdminUserCacheUid == uid &&
        _isAdminUserCacheAt != null &&
        DateTime.now().difference(_isAdminUserCacheAt!) < _adminCacheDuration &&
        _isAdminUserCacheValue != null;
  }

  bool _shouldOpenCacheHit(String uid) {
    return _shouldOpenCacheUid == uid &&
        _shouldOpenCacheAt != null &&
        DateTime.now().difference(_shouldOpenCacheAt!) < _adminCacheDuration &&
        _shouldOpenCacheValue != null;
  }

  Map<String, dynamic> _mapMeToUserDoc() {
    final me = BackendIdentityController.instance.me;
    if (me == null) return <String, dynamic>{};
    final r = me.role.trim().toLowerCase();
    return <String, dynamic>{
      'role': r,
      'email': me.email,
      'uid': me.firebaseUid,
      if (r == PermissionService.roleAdmin || r == PermissionService.roleSystemInternal) 'isAdmin': true,
    };
  }

  /// بث بيانات بديلة لوثيقة `users/{uid}` — مأخوذة من `/auth/me` فقط (بدون Firestore).
  Stream<Map<String, dynamic>?> watchCurrentUserDoc() {
    if (Firebase.apps.isEmpty) {
      return const Stream<Map<String, dynamic>?>.empty();
    }
    _userDocController ??= StreamController<Map<String, dynamic>?>.broadcast(
      onListen: () {
        void push() {
          _userDocController?.add(_mapMeToUserDoc());
        }

        push();
        _userDocIdentitySub?.cancel();
        _userDocIdentitySub = BackendIdentityController.instance.identityUpdates.listen((_) => push());
      },
      onCancel: () {
        if (_userDocController != null && !_userDocController!.hasListener) {
          _userDocIdentitySub?.cancel();
          _userDocIdentitySub = null;
        }
      },
    );
    return _userDocController!.stream;
  }

  Stream<bool> watchIsAdmin() {
    if (Firebase.apps.isEmpty) return Stream<bool>.value(false);
    return FirebaseAuth.instance.authStateChanges().asyncExpand((User? user) {
      if (user == null) {
        return Stream<bool>.value(false);
      }
      return _streamFullAdminFromBackend(user).map((s) => s.showAdminLink);
    });
  }

  Stream<FullAdminDrawerState> _streamFullAdminFromBackend(User user) {
    late StreamController<FullAdminDrawerState> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<FullAdminDrawerState>(
      onListen: () {
        void emit() {
          if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
          final c = BackendIdentityController.instance;
          final show = c.isBackendFullAdmin;
          controller.add(FullAdminDrawerState(
            showAdminLink: show,
            rawRoleFromFirestore: c.me?.role,
            effectiveStaffRole: show ? PermissionService.roleAdmin : null,
          ));
        }

        emit();
        sub = BackendIdentityController.instance.identityUpdates.listen((_) => emit());
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<FullAdminDrawerState> watchFullAdminDrawerState() {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const FullAdminDrawerState(showAdminLink: false));
    }
    return FirebaseAuth.instance.authStateChanges().asyncExpand((User? user) {
      if (user == null) {
        return Stream.value(const FullAdminDrawerState(showAdminLink: false));
      }
      return _streamFullAdminFromBackend(user);
    });
  }

  Stream<bool> watchIsFullAdminUser() => watchFullAdminDrawerState().map((s) => s.showAdminLink);

  Future<void> setUserStaffRole({
    required String uid,
    required String newRole,
  }) async {
    final n = PermissionService.normalizeRole(newRole);
    if (n == null) return;
    final res = await BackendAdminClient.instance.updateUser(uid, role: n);
    if (res == null) return;
  }

  Future<bool> isAdminUser(String uid) async {
    if (Firebase.apps.isEmpty) return false;
    final id = uid.trim();
    if (id.isEmpty) return false;
    if (_isAdminUserCacheHit(id)) {
      return _isAdminUserCacheValue!;
    }
    Future<bool> readOnce() async {
      final cur = FirebaseAuth.instance.currentUser;
      if (cur != null && cur.uid == id) {
        await BackendIdentityController.instance.refresh();
        return BackendIdentityController.instance.isBackendFullAdmin;
      }
      return false;
    }

    try {
      final v = await readOnce();
      _isAdminUserCacheUid = id;
      _isAdminUserCacheAt = DateTime.now();
      _isAdminUserCacheValue = v;
      return v;
    } on Object {
      debugPrint('isAdminUser (will retry)');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        final v = await readOnce();
        _isAdminUserCacheUid = id;
        _isAdminUserCacheAt = DateTime.now();
        _isAdminUserCacheValue = v;
        return v;
      } on Object {
        debugPrint('isAdminUser failed');
        return false;
      }
    }
  }

  Future<bool> shouldOpenAdminDashboard(User user) async {
    if (Firebase.apps.isEmpty) return false;
    final uid = user.uid;
    if (_shouldOpenCacheHit(uid)) {
      return _shouldOpenCacheValue!;
    }

    Future<bool> readBackend() async {
      await BackendIdentityController.instance.refresh();
      return BackendIdentityController.instance.isBackendFullAdmin;
    }

    try {
      final v = await readBackend();
      _shouldOpenCacheUid = uid;
      _shouldOpenCacheAt = DateTime.now();
      _shouldOpenCacheValue = v;
      return v;
    } on Object {
      debugPrint('shouldOpenAdminDashboard (will retry)');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        final v = await readBackend();
        _shouldOpenCacheUid = uid;
        _shouldOpenCacheAt = DateTime.now();
        _shouldOpenCacheValue = v;
        return v;
      } on Object {
        debugPrint('shouldOpenAdminDashboard failed');
        return false;
      }
    }
  }

  Future<FeatureState<List<TechnicianJoinRequest>>> fetchPendingTechnicianJoinRequests() async {
    final raw = await BackendAdminClient.instance.fetchTechnicianJoinRequests();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('Failed to load technician join requests.');
    final out = <TechnicianJoinRequest>[];
    for (final e in items) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      if ((m['status'] as String? ?? '').trim() != 'pending') continue;
      out.add(TechnicianJoinRequest.fromJson(m));
    }
    return FeatureState.success(out);
  }

  Future<FeatureState<FeatureUnit>> approveTechnicianRequest(
    TechnicianJoinRequest req, {
    String? reviewedBy,
  }) async {
    final actor = FirebaseAuth.instance.currentUser;
    final res = await BackendAdminClient.instance.patchTechnicianJoinRequest(
      req.id,
      status: 'approved',
      reviewedBy: reviewedBy ?? actor?.uid,
    );
    if (res == null) return FeatureState.failure('تعذر قبول الطلب عبر الخادم');
    final uid = req.email.trim().isEmpty ? null : await _firebaseUidByEmailLookup(req.email);
    if (uid != null && uid.isNotEmpty) {
      try {
        await UserNotificationsRepository.sendNotificationToUser(
          userId: uid,
          title: 'تم قبول طلب الانضمام كفني',
          body:
              'مرحباً ${req.displayName}، تم قبول طلبك. يمكنك الآن استقبال طلبات الصيانة من التطبيق.',
          type: 'technician_request_approved',
          referenceId: req.id,
        );
      } on Object {
        debugPrint('[AdminRepository] approveTechnicianRequest notification failed');
      }
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<String> _firebaseUidByEmailLookup(String email) async {
    final u = await BackendAdminClient.instance.fetchUsers(limit: 100, offset: 0);
    final items = u?['items'];
    if (items is! List) return '';
    final key = email.trim().toLowerCase();
    for (final e in items) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final em = (m['email'] as String?)?.trim().toLowerCase() ?? '';
      if (em == key) {
        return (m['firebase_uid'] as String?)?.trim() ?? '';
      }
    }
    return '';
  }

  Future<FeatureState<FeatureUnit>> rejectTechnicianRequest(
    TechnicianJoinRequest req, {
    required String reviewedBy,
    required String rejectionReason,
  }) async {
    final reason = rejectionReason.trim();
    if (reason.isEmpty) {
      return FeatureState.failure('سبب الرفض مطلوب');
    }
    final res = await BackendAdminClient.instance.patchTechnicianJoinRequest(
      req.id,
      status: 'rejected',
      rejectionReason: reason,
      reviewedBy: reviewedBy,
    );
    if (res == null) return FeatureState.failure('تعذر رفض الطلب عبر الخادم');
    final uid = await _firebaseUidByEmailLookup(req.email);
    if (uid.isEmpty) return FeatureState.success(FeatureUnit.value);
    try {
      await UserNotificationsRepository.sendNotificationToUser(
        userId: uid,
        title: 'تم رفض طلب الانضمام كفني',
        body: 'سبب الرفض: $reason',
        type: 'technician_request_rejected',
        referenceId: req.id,
      );
    } on Object {
      debugPrint('[AdminRepository] rejectTechnicianRequest notification failed');
    }
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteTechnician(String technicianDocId) async {
    return FeatureState.adminMissingEndpoint('admin_technician_delete');
  }

  Future<FeatureState<FeatureUnit>> setTechnicianStatus(String technicianDocId, String status) async {
    final res = await BackendAdminClient.instance.updateTechnicianStatus(technicianDocId, status);
    if (res == null) return FeatureState.failure('تعذر تحديث حالة الفني');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateTechnicianProfile(String technicianDocId, Map<String, dynamic> patch) async {
    final res = await BackendAdminClient.instance.updateTechnicianProfile(
      technicianDocId,
      displayName: patch['displayName'] as String?,
      email: patch['email'] as String?,
      phone: patch['phone'] as String?,
      city: patch['city'] as String?,
      category: patch['category'] as String?,
      specialties: (patch['specialties'] as List?)?.map((e) => e.toString()).toList(),
      cities: (patch['cities'] as List?)?.map((e) => e.toString()).toList(),
      status: patch['status'] as String?,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث ملف الفني');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> setUserBanned(String userDocId, bool banned, {String? reason}) async {
    final res = await BackendAdminClient.instance.updateUser(
      userDocId,
      banned: banned,
      bannedReason: reason,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث حالة الحظر');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteUserDocument(String userDocId) async {
    final res = await BackendAdminClient.instance.deleteUser(userDocId);
    if (res == null) return FeatureState.failure('تعذر حذف المستخدم عبر الخادم');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> adjustWalletBalance({
    required String userEmail,
    required double amountDelta,
    required String adminEmail,
    required String note,
  }) async {
    final list = await BackendAdminClient.instance.fetchUsers(limit: 200, offset: 0);
    final items = list?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب المستخدمين');
    final key = userEmail.trim().toLowerCase();
    Map<String, dynamic>? row;
    for (final e in items) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      if ((m['email'] as String?)?.trim().toLowerCase() == key) {
        row = m;
        break;
      }
    }
    if (row == null) return FeatureState.failure('المستخدم غير موجود في الخادم');
    final id = row['id']?.toString() ?? row['firebase_uid']?.toString() ?? '';
    if (id.isEmpty) return FeatureState.failure('معرّف المستخدم غير صالح');
    final walletRaw = row['wallet_balance'];
    if (walletRaw == null) return FeatureState.failure('INVALID_NUMERIC_DATA');
    final cur = (walletRaw as num?)?.toDouble();
    if (cur == null) return FeatureState.failure('INVALID_NUMERIC_DATA');
    final res = await BackendAdminClient.instance.updateUser(id, walletBalance: cur + amountDelta);
    if (res == null) return FeatureState.failure('تعذر تحديث المحفظة');
    debugPrint('[AdminRepository] wallet adjust $note by $adminEmail');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<Map<String, dynamic>?> fetchMigrationStatusPayload() async {
    final raw = await BackendAdminClient.instance.fetchMigrationStatus();
    return raw?['payload'] is Map<String, dynamic> ? raw!['payload'] as Map<String, dynamic> : <String, dynamic>{};
  }

  Future<FeatureState<FeatureUnit>> patchMigrationStatusPayload(Map<String, dynamic> payload) async {
    final res = await BackendAdminClient.instance.patchMigrationStatus(payload);
    if (res == null) return FeatureState.failure('تعذر حفظ حالة الهجرة');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateReportFields(String reportId, Map<String, dynamic> fields) async {
    final res = await BackendAdminClient.instance.patchReport(
      reportId,
      status: fields['status'] as String?,
      subject: fields['subject'] as String?,
      bodyText: fields['body'] as String? ?? fields['bodyText'] as String?,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث البلاغ');
    return FeatureState.success(FeatureUnit.value);
  }

  /// لوحة المؤشرات — تُحمَّل من واجهات التحليلات في الخادم.
  Future<AdminOverviewMetrics> loadOverviewDashboard() => loadAdminOverviewMetrics();

  Future<FeatureState<List<Map<String, dynamic>>>> fetchCoupons() async {
    final raw = await BackendAdminClient.instance.fetchCoupons(limit: 200, offset: 0);
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب الكوبونات');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> createCoupon({
    required String code,
    required String name,
    String status = 'active',
  }) async {
    final res = await BackendAdminClient.instance.createCoupon(code: code, name: name, status: status);
    if (res == null) return FeatureState.failure('تعذر إنشاء الكوبون');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateCoupon(String id, {String? code, String? name, String? status}) async {
    final res = await BackendAdminClient.instance.updateCoupon(id, code: code, name: name, status: status);
    if (res == null) return FeatureState.failure('تعذر تحديث الكوبون');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteCoupon(String id) async {
    final res = await BackendAdminClient.instance.deleteCoupon(id);
    if (res == null) return FeatureState.failure('تعذر حذف الكوبون');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchPromotions() async {
    final raw = await BackendAdminClient.instance.fetchPromotions(limit: 200, offset: 0);
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب العروض');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> createPromotion({
    required String name,
    String promoType = 'percentage',
    String status = 'active',
  }) async {
    final res = await BackendAdminClient.instance.createPromotion(name: name, promoType: promoType, status: status);
    if (res == null) return FeatureState.failure('تعذر إنشاء العرض');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updatePromotion(String id, {String? name, String? promoType, String? status}) async {
    final res = await BackendAdminClient.instance.updatePromotion(
      id,
      name: name,
      promoType: promoType,
      status: status,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث العرض');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deletePromotion(String id) async {
    final res = await BackendAdminClient.instance.deletePromotion(id);
    if (res == null) return FeatureState.failure('تعذر حذف العرض');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchTenders() async {
    final raw = await BackendAdminClient.instance.fetchTenders();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب المناقصات');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> updateTender(String id, {String? status, String? title}) async {
    final res = await BackendAdminClient.instance.updateTender(id, status: status, title: title);
    if (res == null) return FeatureState.failure('تعذر تحديث المناقصة');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchSupportTickets() async {
    final raw = await BackendAdminClient.instance.fetchSupportTickets();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب تذاكر الدعم');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> updateSupportTicket(String id, {String? status, String? subject}) async {
    final res = await BackendAdminClient.instance.updateSupportTicket(id, status: status, subject: subject);
    if (res == null) return FeatureState.failure('تعذر تحديث تذكرة الدعم');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchWholesalers() async {
    final raw = await BackendAdminClient.instance.fetchWholesalers();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب تجار الجملة');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> updateWholesaler(
    String id, {
    String? status,
    String? name,
    String? category,
    String? city,
    double? commission,
  }) async {
    final res = await BackendAdminClient.instance.updateWholesaler(
      id,
      status: status,
      name: name,
      category: category,
      city: city,
      commission: commission,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث تاجر الجملة');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchCategories({String kind = 'all'}) async {
    final raw = await BackendAdminClient.instance.fetchCategories(kind: kind);
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب التصنيفات');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> createCategory({
    required String name,
    String kind = 'general',
    String status = 'active',
  }) async {
    final res = await BackendAdminClient.instance.createCategory(name: name, kind: kind, status: status);
    if (res == null) return FeatureState.failure('تعذر إنشاء التصنيف');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateCategory(String id, {String? name, String? kind, String? status}) async {
    final res = await BackendAdminClient.instance.updateCategory(id, name: name, kind: kind, status: status);
    if (res == null) return FeatureState.failure('تعذر تحديث التصنيف');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteCategory(String id) async {
    final res = await BackendAdminClient.instance.deleteCategory(id);
    if (res == null) return FeatureState.failure('تعذر حذف التصنيف');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<Map<String, dynamic>>> fetchSettings() async {
    final raw = await BackendAdminClient.instance.fetchSettings();
    final payload = raw?['payload'];
    if (payload is Map<String, dynamic>) return FeatureState.success(payload);
    if (payload is Map) return FeatureState.success(Map<String, dynamic>.from(payload));
    return FeatureState.failure('تعذر جلب الإعدادات');
  }

  Future<FeatureState<FeatureUnit>> updateSettings(Map<String, dynamic> payload) async {
    final res = await BackendAdminClient.instance.updateSettings(payload);
    if (res == null) return FeatureState.failure('تعذر حفظ الإعدادات');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchMarketplaceProducts({
    String? subCategoryId,
    String? storeId,
    String? sectionId,
    String? search,
  }) async {
    final raw = await BackendAdminClient.instance.fetchFilteredProducts(
      subCategoryId: subCategoryId,
      storeId: storeId,
      sectionId: sectionId,
      search: search,
      limit: 200,
      offset: 0,
    );
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب المنتجات');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> createMarketplaceProduct({
    required String storeId,
    required String name,
    String? subCategoryId,
    String? description,
    double? price,
    String? image,
    int? stock,
    bool isActive = true,
  }) async {
    final res = await BackendAdminClient.instance.createMarketplaceProduct(
      storeId: storeId,
      subCategoryId: subCategoryId,
      name: name,
      description: description,
      price: price,
      image: image,
      stock: stock,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر إنشاء المنتج');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateMarketplaceProduct(
    String id, {
    String? storeId,
    String? subCategoryId,
    String? name,
    String? description,
    double? price,
    String? image,
    int? stock,
    bool? isActive,
  }) async {
    final res = await BackendAdminClient.instance.updateMarketplaceProduct(
      id,
      storeId: storeId,
      subCategoryId: subCategoryId,
      name: name,
      description: description,
      price: price,
      image: image,
      stock: stock,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث المنتج');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteMarketplaceProduct(String id) async {
    final res = await BackendAdminClient.instance.deleteMarketplaceProduct(id);
    if (res == null) return FeatureState.failure('تعذر حذف المنتج');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> bulkUpdateMarketplaceStock(List<Map<String, dynamic>> items) async {
    final res = await BackendAdminClient.instance.bulkUpdateMarketplaceStock(items);
    if (res == null) return FeatureState.failure('تعذر تحديث المخزون المجمع');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateProductBoost(
    String productId, {
    bool? isBoosted,
    bool? isTrending,
  }) async {
    final res = await BackendAdminClient.instance.updateProductBoost(
      productId,
      isBoosted: isBoosted,
      isTrending: isTrending,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث حالة تمييز المنتج');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateStoreFeatures(
    String storeId, {
    bool? isFeatured,
    bool? isBoosted,
    String? boostExpiresAt,
  }) async {
    final res = await BackendAdminClient.instance.updateStoreFeatures(
      storeId,
      isFeatured: isFeatured,
      isBoosted: isBoosted,
      boostExpiresAt: boostExpiresAt,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث خصائص المتجر');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchBoostRequests({String status = 'all'}) async {
    final raw = await BackendAdminClient.instance.fetchBoostRequests(status: status);
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب طلبات الترويج');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> patchBoostRequestStatus(
    String id, {
    required String status,
  }) async {
    final res = await BackendAdminClient.instance.patchBoostRequestStatus(id, status: status);
    if (res == null) return FeatureState.failure('تعذر تحديث حالة طلب الترويج');
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchSubCategories({
    required String sectionId,
  }) async {
    final raw = await BackendAdminClient.instance.fetchSubCategories(sectionId: sectionId);
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب الأقسام الفرعية');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<FeatureUnit>> createSubCategory({
    required String homeSectionId,
    required String name,
    String? image,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    final res = await BackendAdminClient.instance.createSubCategory(
      homeSectionId: homeSectionId,
      name: name,
      image: image,
      sortOrder: sortOrder,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر إنشاء القسم الفرعي');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateSubCategory(
    String id, {
    String? homeSectionId,
    String? name,
    String? image,
    int? sortOrder,
    bool? isActive,
  }) async {
    final res = await BackendAdminClient.instance.updateSubCategory(
      id,
      homeSectionId: homeSectionId,
      name: name,
      image: image,
      sortOrder: sortOrder,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث القسم الفرعي');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteSubCategory(String id) async {
    final res = await BackendAdminClient.instance.deleteSubCategory(id);
    if (res == null) return FeatureState.failure('تعذر حذف القسم الفرعي');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchHomeSections() async {
    final raw = await BackendAdminClient.instance.fetchHomeSections();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب الأقسام الرئيسية');
    return FeatureState.success(items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<FeatureState<Map<String, dynamic>>> fetchHomeCms() async {
    final raw = await BackendAdminClient.instance.fetchHomeCms();
    if (raw == null) return FeatureState.failure('تعذر جلب إعدادات الصفحة الرئيسية');
    return FeatureState.success(Map<String, dynamic>.from(raw));
  }

  Future<FeatureState<FeatureUnit>> patchHomeCms(Map<String, dynamic> body) async {
    final res = await BackendAdminClient.instance.patchHomeCms(body);
    if (res == null) return FeatureState.failure('تعذر حفظ إعدادات الصفحة الرئيسية');
    HomeRepository.instance.invalidateAll();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<List<Map<String, dynamic>>>> fetchStoreTypes() async {
    final raw = await BackendAdminClient.instance.fetchStoreTypes();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('تعذر جلب أنواع المتاجر');
    return FeatureState.success(
      items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    );
  }

  Future<FeatureState<FeatureUnit>> createStoreType({
    required String name,
    required String key,
    String? icon,
    String? image,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    final res = await BackendAdminClient.instance.createStoreType(
      name: name,
      key: key,
      icon: icon,
      image: image,
      displayOrder: displayOrder,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر إنشاء نوع المتجر');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateStoreType(
    String id, {
    String? name,
    String? key,
    String? icon,
    String? image,
    int? displayOrder,
    bool? isActive,
  }) async {
    final res = await BackendAdminClient.instance.updateStoreType(
      id,
      name: name,
      key: key,
      icon: icon,
      image: image,
      displayOrder: displayOrder,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث نوع المتجر');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteStoreType(String id) async {
    final res = await BackendAdminClient.instance.deleteStoreType(id);
    if (res == null) return FeatureState.failure('تعذر حذف نوع المتجر');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> createHomeSection({
    required String name,
    required String type,
    String? storeTypeId,
    String? image,
    bool isActive = true,
  }) async {
    final res = await BackendAdminClient.instance.createHomeSection(
      name: name,
      type: type,
      storeTypeId: storeTypeId,
      image: image,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر إنشاء القسم الرئيسية');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> updateHomeSection(
    String id, {
    String? name,
    String? type,
    String? storeTypeId,
    String? image,
    bool? isActive,
  }) async {
    final res = await BackendAdminClient.instance.updateHomeSection(
      id,
      name: name,
      type: type,
      storeTypeId: storeTypeId,
      image: image,
      isActive: isActive,
    );
    if (res == null) return FeatureState.failure('تعذر تحديث القسم الرئيسية');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }

  Future<FeatureState<FeatureUnit>> deleteHomeSection(String id) async {
    final res = await BackendAdminClient.instance.deleteHomeSection(id);
    if (res == null) return FeatureState.failure('تعذر حذف القسم الرئيسية');
    _invalidateStoreTaxonomyCaches();
    return FeatureState.success(FeatureUnit.value);
  }
}
