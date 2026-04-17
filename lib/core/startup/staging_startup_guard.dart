import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';

abstract final class StagingStartupGuard {
  /// Staging checks are **best-effort** Ã¢â‚¬â€ never block app launch.
  static Future<void> verifyOrThrow() async {
    if (!BackendOrdersConfig.stagingMode) return;
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      debugPrint('[StagingStartupGuard] skip: empty base URL');
      return;
    }

    try {
      final health = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 8));
      if (health.statusCode < 200 || health.statusCode >= 500) {
        debugPrint('[StagingStartupGuard] /health unhealthy ${health.statusCode} (continuing)');
      }

      final stores = await http.get(Uri.parse('$base/stores')).timeout(const Duration(seconds: 8));
      if (!(stores.statusCode == 200 || stores.statusCode == 401 || stores.statusCode == 403)) {
        debugPrint('[StagingStartupGuard] /stores unexpected ${stores.statusCode} (continuing)');
      }

      final serviceRequests =
          await http.get(Uri.parse('$base/service-requests')).timeout(const Duration(seconds: 8));
      if (!(serviceRequests.statusCode == 200 ||
          serviceRequests.statusCode == 401 ||
          serviceRequests.statusCode == 403)) {
        debugPrint(
          '[StagingStartupGuard] /service-requests unexpected ${serviceRequests.statusCode} (continuing)',
        );
      }

      debugPrint(
        jsonEncode({
          'kind': 'flutter_staging_startup_verified',
          'health': health.statusCode,
          'stores': stores.statusCode,
          'serviceRequests': serviceRequests.statusCode,
        }),
      );
    } on Object {
      debugPrint('[StagingStartupGuard] staging verification failed (continuing): unexpected error\n$StackTrace.current');
    }
  }
}

