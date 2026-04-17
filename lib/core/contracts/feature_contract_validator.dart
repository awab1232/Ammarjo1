import 'package:flutter/foundation.dart' show debugPrint;

import '../config/backend_orders_config.dart';
import 'feature_contract_registry.dart';

/// Startup validation: logs violations and records blocked **features** (not whole app).
abstract final class FeatureContractValidator {
  static final Set<String> blockedFeatureIds = <String>{};

  /// Call after [BackendOrdersConfig] is readable (e.g. early in `_appMain`).
  static void validateAtStartup() {
    blockedFeatureIds.clear();
    final base = BackendOrdersConfig.baseUrl.trim();
    for (final c in FeatureContractRegistry.all) {
      if (!c.hasBackend) continue;
      if (c.isCritical && base.isEmpty) {
        debugPrint(
          '[FeatureContractValidator] CRITICAL_MISSING_FEATURE: ${c.id} (${c.name}) — '
          'BACKEND_ORDERS_BASE_URL empty; feature blocked until configured.',
        );
        blockedFeatureIds.add(c.id);
      }
    }
    if (blockedFeatureIds.isEmpty) {
      debugPrint('[FeatureContractValidator] PASS (no critical backend violations logged)');
    }
  }

  static bool isBlocked(String featureId) => blockedFeatureIds.contains(featureId);
}
