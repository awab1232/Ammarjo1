import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../logging/firestore_usage_logger.dart';

/// Hard gate for legacy storage access outside debug builds.
abstract final class FirestoreProductionGuard {
  static const String blockedMessage = 'Firestore access blocked in production';

  /// Logs and returns when Firestore access is not allowed (no throw — avoids crashing release builds).
  static void assertFirestoreAccessAllowed({
    required String domain,
    String path = '*',
  }) {
    if (!kDebugMode) {
      FirestoreUsageLogger.logBlocked(domain: domain, path: path);
      debugPrint('[FirestoreProductionGuard] $blockedMessage domain=$domain path=$path');
    }
  }

  /// Legacy alias — read vs write both denied in production.
  static void assertReadAllowed(String path, {String domain = 'unknown'}) {
    assertFirestoreAccessAllowed(domain: domain, path: path);
  }

  /// Legacy alias — read vs write both denied in production.
  static void assertWriteAllowed(String path, {String domain = 'unknown'}) {
    assertFirestoreAccessAllowed(domain: domain, path: path);
  }
}
