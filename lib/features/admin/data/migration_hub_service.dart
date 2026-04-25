import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';

import 'backend_admin_client.dart';

/// إدارة حالة الهجرة في PostgreSQL. فحص WooCommerce أزيل — الكتالوج عبر NestJS فقط.
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
    if (res == null) {
      developer.log('MigrationHub: patchMigrationStatus returned null', name: 'MigrationHub');
      return;
    }
  }

  // REMOVED: legacy WooCommerce — use BackendOrdersClient instead
  /// يسجّل على الخادم أن فحص Woo أزيل؛ الكتالوج يُدار عبر API فقط.
  Future<MigrationHubResult> run({
    void Function(String message)? onProgress,
  }) async {
    if (!Firebase.apps.isNotEmpty) {
      developer.log('MigrationHub: Firebase not initialized', name: 'MigrationHub');
      return MigrationHubResult(categoriesCount: 0, productsCount: 0);
    }

    onProgress?.call('تعطيل فحص WooCommerce: الاعتماد على الخادم (NestJS) فقط.');

    await _patchStatus({
      'phase': 'disabled',
      'migrationCompleted': false,
      'lastError': null,
      'note': 'WooCommerce client removed; catalog is server-side only.',
      'disabledAt': DateTime.now().toUtc().toIso8601String(),
    });

    return MigrationHubResult(categoriesCount: 0, productsCount: 0);
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
