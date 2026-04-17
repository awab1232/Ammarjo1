import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/backend_orders_config.dart';

/// Non-blocking backend probes Ã¢â‚¬â€ **never** throws; logs only (app must boot offline-degraded).
abstract final class RuntimeSafetyEnforcer {
  /// Renamed from enforce-or-throw: probes `/health` and optional internal detailed health.
  static Future<void> probeBackendHealthNonBlocking() async {
    final base = BackendOrdersConfig.baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) {
      debugPrint('[RuntimeSafetyEnforcer] skip health probe: empty base URL');
      return;
    }
    try {
      final health = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 12));
      if (health.statusCode < 200 || health.statusCode >= 500) {
        debugPrint(
          '[RuntimeSafetyEnforcer] /health non-OK ${health.statusCode} Ã¢â‚¬â€ continuing boot',
        );
      } else {
        debugPrint('[RuntimeSafetyEnforcer] /health OK');
      }

      const internalKey = String.fromEnvironment('INTERNAL_API_KEY', defaultValue: '');
      if (internalKey.trim().isNotEmpty) {
        try {
          final detailed = await http
              .get(
                Uri.parse('$base/internal/health/detailed'),
                headers: {'x-internal-api-key': internalKey.trim()},
              )
              .timeout(const Duration(seconds: 12));
          if (detailed.statusCode < 200 || detailed.statusCode >= 300) {
            debugPrint(
              '[RuntimeSafetyEnforcer] /internal/health/detailed ${detailed.statusCode} Ã¢â‚¬â€ ignored',
            );
          }
        } on Object {
          debugPrint('[RuntimeSafetyEnforcer] internal health probe failed (ignored): unexpected error\n$StackTrace.current');
        }
      }
    } on Object {
      debugPrint('[RuntimeSafetyEnforcer] health probe failed (ignored): unexpected error\n$StackTrace.current');
    }
  }
}

