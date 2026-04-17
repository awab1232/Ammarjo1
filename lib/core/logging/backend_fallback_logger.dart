import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kDebugMode;
import 'package:sentry_flutter/sentry_flutter.dart';

import '../monitoring/sentry_safe.dart';

/// Bumps on each [BackendFallbackLogger.logBackendFallbackTriggered] (dev-only) so UI can rebuild.
final ValueNotifier<int> backendFallbackUiTick = ValueNotifier<int>(0);

/// Structured observability when the app uses Firebase or local data because the orders API was skipped, failed, or returned nothing.
abstract final class BackendFallbackLogger {
  /// Incremented whenever [logBackendFallbackTriggered] runs (also drives dev banner).
  static int recordedFallbackCount = 0;

  /// Always emit a traceable record (console / `dart:developer` in all modes).
  static void logBackendFallbackTriggered({
    required String flow,
    required String reason,
    Map<String, Object?>? extra,
  }) {
    recordedFallbackCount++;
    if (kDebugMode) {
      backendFallbackUiTick.value++;
    }
    final payload = <String, Object?>{
      'kind': 'backend_fallback_triggered',
      'userId': null,
      'tenantId': null,
      'endpoint': flow,
      'flow': flow,
      'reason': reason,
      if (extra != null) ...extra,
    };
    final line = jsonEncode(payload);
    developer.log(line, name: 'BackendFallback', level: 900);
    // ignore: avoid_print
    print(line);
    if (kDebugMode) {
      debugPrint(line);
    }
    final unified = <String, Object?>{
      'kind': 'data_fallback_used',
      'context': flow,
      'endpoint': flow,
      'entity': (extra?['entity'] ?? 'unknown'),
      'reason': reason,
      if (extra != null) ...extra,
    };
    final unifiedLine = jsonEncode(unified);
    developer.log(unifiedLine, name: 'DataFallback', level: 900);
    // ignore: avoid_print
    print(unifiedLine);
    sentryCaptureMessageSafe(
      'backend_fallback_triggered',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope.setContexts('backend_fallback', payload);
      },
    );
  }

  static void logFirestoreLegacyEvent({
    required String kind,
    required String module,
    required String reason,
    String? userId,
    Map<String, Object?>? extra,
  }) {
    final payload = <String, Object?>{
      'kind': kind,
      'module': module,
      'reason': reason,
      'userId': userId,
      if (extra != null) ...extra,
    };
    final line = jsonEncode(payload);
    developer.log(line, name: 'FirestoreLegacy', level: 900);
    // ignore: avoid_print
    print(line);
    if (kDebugMode) {
      debugPrint(line);
    }
  }

  static void logBackendFailureNoFallback({
    required String flow,
    required String reason,
    Map<String, Object?>? extra,
  }) {
    final payload = <String, Object?>{
      'kind': 'backend_failure_no_fallback',
      'userId': null,
      'tenantId': null,
      'endpoint': flow,
      'flow': flow,
      'reason': reason,
      if (extra != null) ...extra,
    };
    final line = jsonEncode(payload);
    developer.log(line, name: 'BackendFailureNoFallback', level: 1000);
    // ignore: avoid_print
    print(line);
    if (kDebugMode) {
      debugPrint(line);
    }
  }

  static void logFirebaseFallbackInProductionWarning({
    required String flow,
    required String reason,
  }) {
    const prefix = 'WARNING: Firebase fallback triggered in production';
    final payload = jsonEncode({
      'kind': 'backend_fallback_triggered',
      'userId': null,
      'tenantId': null,
      'endpoint': flow,
      'flow': flow,
      'reason': reason,
      'environment': 'production',
    });
    developer.log('$prefix $payload', name: 'BackendFallback', level: 1000);
    // ignore: avoid_print
    print('$prefix $payload');
    if (kDebugMode) {
      debugPrint('$prefix $payload');
    }
  }

  /// WARNING: `BACKEND_ORDERS_BASE_URL` unset — hybrid/backend features cannot reach the API.
  static void logBackendBaseUrlMissingWarning({required String context}) {
    final payload = <String, Object?>{
      'kind': 'backend_base_url_missing',
      'level': 'WARNING',
      'context': context,
      'message': 'BACKEND_ORDERS_BASE_URL is missing or empty; configure it for backend-driven flows.',
    };
    final line = jsonEncode(payload);
    developer.log(line, name: 'BackendConfig', level: 900);
    // ignore: avoid_print
    print('WARNING: $line');
    if (kDebugMode) {
      debugPrint('WARNING: $line');
    }
  }

  static void enforceFirestoreShutdownPhase({
    required String module,
    required String reason,
    String? userId,
    Map<String, Object?>? extra,
  }) {
    if (kDebugMode) {
      logFirestoreLegacyEvent(
        kind: 'firestore_read_legacy',
        module: module,
        reason: reason,
        userId: userId,
        extra: extra,
      );
      return;
    }
    logFirestoreLegacyEvent(
      kind: 'firestore_write_blocked',
      module: module,
      reason: reason,
      userId: userId,
      extra: extra,
    );
    throw StateError('FIRESTORE_SHUTDOWN_PHASE_ACTIVE');
  }
}
