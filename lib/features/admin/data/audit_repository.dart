import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/contracts/feature_state.dart';
import 'backend_admin_client.dart';

/// سجلات التدقيق — `GET /admin/rest/audit-logs`.
abstract final class AuditRepository {
  static Future<FeatureState<List<Map<String, dynamic>>>> fetchAuditLogsPage({
    required int limit,
    int offset = 0,
  }) async {
    try {
      final raw = await BackendAdminClient.instance.fetchAuditLogs(limit: limit, offset: offset);
      final items = raw?['items'];
      if (items is! List) return FeatureState.failure('Audit logs payload is invalid.');
      return FeatureState.success(
        items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    } on Object {
      debugPrint('[AuditRepository] fetchAuditLogsPage failed');
      return FeatureState.failure('Failed to load audit logs.');
    }
  }

  /// يُسجَّل على الخادم ضمنيًا عند استدعاءات الإدارة؛ هنا نُبقي تسجيلاً محلياً فقط.
  static Future<void> logAction({
    required String userId,
    required String userEmail,
    required String action,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? details,
  }) async {
    debugPrint(
      '[AuditRepository] $action $targetType:$targetId by $userEmail (${details?.keys.join(',')})',
    );
  }
}
