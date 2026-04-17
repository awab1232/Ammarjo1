import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';

import '../../store/data/woo_api_service.dart';
import 'backend_admin_client.dart';

/// فحص Woo عبر API وتسجيل ملخص الحالة في PostgreSQL (`admin_migration_status`) — بدون Firestore.
class MigrationHubService {
  MigrationHubService._();
  static final MigrationHubService instance = MigrationHubService._();

  Future<void> _patchStatus(Map<String, dynamic> patch) async {
    final cur = await BackendAdminClient.instance.fetchMigrationStatus();
    final existing = cur?['payload'];
    final merged = <String, dynamic>{
      if (existing is Map<String, dynamic>) ...existing,
      ...patch,
    };
    final res = await BackendAdminClient.instance.patchMigrationStatus(merged);
    if (res == null) throw StateError('تعذر حفظ حالة الهجرة في الخادم');
  }

  /// يجلب أعداد الأقسام والمنتجات من Woo ويسجّلها في الخادم (لا يكتب كتالوجاً في Firestore).
  Future<MigrationHubResult> run({
    required WooApiService api,
    void Function(String message)? onProgress,
  }) async {
    if (!Firebase.apps.isNotEmpty) {
      throw StateError('Firebase غير مهيأ');
    }

    await _patchStatus({
      'phase': 'starting',
      'migrationCompleted': false,
      'lastError': null,
      'wooProbeAt': DateTime.now().toUtc().toIso8601String(),
    });

    try {
      onProgress?.call('جاري جلب الأقسام من WooCommerce…');

      late final List<Map<String, dynamic>> rawCategories;
      try {
        rawCategories = await api.fetchAllProductCategoriesRawForMigration();
      } on Object {
        developer.log(
          'MigrationHub: fetch categories failed',
          name: 'MigrationHub',
        );
        rethrow;
      }
      rawCategories.sort((a, b) {
        final pa = (a['parent'] as num?)?.toInt() ?? 0;
        final pb = (b['parent'] as num?)?.toInt() ?? 0;
        if (pa != pb) return pa.compareTo(pb);
        final ida = (a['id'] as num?)?.toInt() ?? 0;
        final idb = (b['id'] as num?)?.toInt() ?? 0;
        return ida.compareTo(idb);
      });

      onProgress?.call('جاري جلب المنتجات من WooCommerce…');
      late final List<Map<String, dynamic>> rawProducts;
      try {
        rawProducts = await api.fetchAllProductsRawForMigration();
      } on Object {
        developer.log(
          'MigrationHub: fetch products failed',
          name: 'MigrationHub',
        );
        rethrow;
      }

      await _patchStatus({
        'phase': 'success',
        'migrationCompleted': true,
        'categoriesCount': rawCategories.length,
        'productsCount': rawProducts.length,
        'lastError': null,
        'note':
            'Woo تمت قراءته فقط؛ الكتالوج الفعلي يُدار على الخادم (PostgreSQL). لا يُكتب إلى Firestore من لوحة الإدارة.',
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });

      return MigrationHubResult(
        categoriesCount: rawCategories.length,
        productsCount: rawProducts.length,
      );
    } on Object {
      await _patchStatus({
        'phase': 'failed',
        'migrationCompleted': false,
        'lastError': 'Unexpected migration error',
      });
      rethrow;
    }
  }

  static String pickPrice(Map<String, dynamic> m) {
    String pick(String k) => m[k]?.toString().trim() ?? '';
    var p = pick('price');
    if (p.isNotEmpty) return p;
    p = pick('regular_price');
    if (p.isNotEmpty) return p;
    p = pick('sale_price');
    if (p.isNotEmpty) return p;
    return '';
  }
}

class MigrationHubResult {
  MigrationHubResult({required this.categoriesCount, required this.productsCount});

  final int categoriesCount;
  final int productsCount;
}
