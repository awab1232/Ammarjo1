import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

/// Structured log when Firestore is touched (audit / migration / hard gate).
abstract final class FirestoreUsageLogger {
  static void logFallback({
    required String domain,
    required String path,
    String? reason,
  }) {
    try {
      debugPrint(
        jsonEncode(<String, dynamic>{
          'kind': 'firestore_fallback_used',
          'domain': domain,
          'path': path,
          'reason': reason,
        }..removeWhere((k, v) => v == null)),
      );
    } on Object {
      /* ignore */
    }
  }

  /// Production denial — use [kind] `firestore_blocked` per shutdown spec.
  static void logBlocked({
    required String domain,
    required String path,
    String? reason,
  }) {
    try {
      debugPrint(
        jsonEncode(<String, dynamic>{
          'kind': 'firestore_blocked',
          'domain': domain,
          'path': path,
          'reason': reason,
        }..removeWhere((k, v) => v == null)),
      );
    } on Object {
      /* ignore */
    }
  }

  @Deprecated('Use [logBlocked] or [logFallback]')
  static void log({
    required String domain,
    required String path,
    required bool blocked,
    String? reason,
  }) {
    if (blocked) {
      logBlocked(domain: domain, path: path, reason: reason);
    } else {
      logFallback(domain: domain, path: path, reason: reason ?? 'debug_access');
    }
  }
}
