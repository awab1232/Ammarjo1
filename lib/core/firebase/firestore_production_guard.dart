import 'package:flutter/foundation.dart' show kDebugMode;

import '../logging/firestore_usage_logger.dart';

/// Hard gate for legacy storage access outside debug builds.
abstract final class FirestoreProductionGuard {
  static const String blockedMessage = 'Firestore access blocked in production';

  /// Throws [Exception] with [blockedMessage] when not in debug mode.
  static void assertFirestoreAccessAllowed({
    required String domain,
    String path = '*',
  }) {
    if (!kDebugMode) {
      FirestoreUsageLogger.logBlocked(domain: domain, path: path);
      throw Exception(blockedMessage);
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
