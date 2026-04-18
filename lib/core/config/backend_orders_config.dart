import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kReleaseMode;

import '../logging/backend_fallback_logger.dart';

/// NestJS orders API — backend-only; no Firestore/catalog fallback.
///
/// **Testing:** set `BACKEND_ORDERS_BASE_URL` via `--dart-define` to your local API (debug only).
abstract final class BackendOrdersConfig {
  /// Production API (HTTPS, no trailing slash). Release builds use this unless a non-dev URL is passed via `BACKEND_ORDERS_BASE_URL`.
  static const String defaultBaseUrl = 'https://api.ammarjo.org';

  /// Debug-only fallback when `BACKEND_ORDERS_BASE_URL` is unset (Android emulator → host machine).
  static const String _debugEmulatorBackendUrl = 'http://10.0.2.2:3000';
  static const bool stagingMode = true;
  static const bool _useBackendOrdersDev = true;
  static const bool _useBackendOrdersReadDev = true;
  static const bool _useBackendOrdersWriteDev = true;
  static const bool _useBackendStoreReadsDev = true;
  static const bool _useBackendProductsReadsDev = true;
  static const bool _useBackendOwnerWritesDev = true;
  static const bool _useBackendCartDev = true;

  /// When `true`, signed-in users persist the store cart via `GET/POST/PATCH/DELETE /cart` (PostgreSQL).
  static bool get useBackendCart =>
      _useBackendCartDev ||
      const bool.fromEnvironment('USE_BACKEND_CART', defaultValue: false);

  /// Backend order pipeline enabled (`USE_BACKEND_ORDERS` or dev defaults).
  static bool get useBackendOrders =>
      _useBackendOrdersDev ||
      const bool.fromEnvironment('USE_BACKEND_ORDERS', defaultValue: false);

  /// Backend order reads (`USE_BACKEND_ORDERS_READ`).
  static bool get useBackendOrdersRead =>
      _useBackendOrdersReadDev ||
      const bool.fromEnvironment('USE_BACKEND_ORDERS_READ', defaultValue: false);

  /// Backend-primary order creation (`USE_BACKEND_ORDERS_WRITE`).
  static bool get useBackendOrdersWrite =>
      _useBackendOrdersWriteDev ||
      const bool.fromEnvironment('USE_BACKEND_ORDERS_WRITE', defaultValue: false);

  /// Backend reads for stores and store categories.
  static bool get useBackendStoreReads =>
      _useBackendStoreReadsDev ||
      const bool.fromEnvironment('USE_BACKEND_STORE_READS', defaultValue: true);

  /// Backend reads for products and catalog categories.
  static bool get useBackendProductsReads =>
      _useBackendProductsReadsDev ||
      const bool.fromEnvironment('USE_BACKEND_PRODUCTS_READS', defaultValue: true);

  /// Owner writes are routed to backend or disabled on Firebase write paths.
  static bool get useBackendOwnerWrites =>
      _useBackendOwnerWritesDev ||
      const bool.fromEnvironment('USE_BACKEND_OWNER_WRITES', defaultValue: false);

  /// 1–100: fraction of (uid, orderId) pairs that attempt backend read when [useBackendOrdersRead] is true.
  /// Use `100` for full rollout; lower for gradual adoption. Invalid values are treated as `100`.
  static const int backendOrdersReadRolloutPercent = 100;

  /// 1–100: fraction of `(uid|order_write)` that attempt backend-primary POST when [useBackendOrdersWrite] is true.
  static const int backendOrdersWriteRolloutPercent = 100;

  /// Max wait for backend GET (non-blocking for first paint).
  static const Duration backendOrdersReadTimeout = Duration(milliseconds: 1500);

  /// Max wait for backend POST during checkout (async; does not block the UI isolate).
  static const Duration backendOrdersWriteTimeout = Duration(seconds: 20);

  /// Base URL without trailing slash. Release → [defaultBaseUrl] (or non-local `BACKEND_ORDERS_BASE_URL`). Debug → define, else [_debugEmulatorBackendUrl].
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('BACKEND_ORDERS_BASE_URL', defaultValue: '');
    final trimmed = fromEnv.trim();

    if (kReleaseMode) {
      if (trimmed.isNotEmpty) {
        if (_isLocalhostUrl(trimmed)) {
          debugPrint(
            '[BackendConfig] BACKEND_ORDERS_BASE_URL is a dev host in release — using $defaultBaseUrl',
          );
          return defaultBaseUrl;
        }
        return trimmed;
      }
      return defaultBaseUrl;
    }

    if (trimmed.isNotEmpty) return trimmed;
    return _debugEmulatorBackendUrl;
  }

  static bool _isLocalhostUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('localhost') ||
        lower.contains('127.0.0.1') ||
        lower.contains('10.0.2.2');
  }

  static bool _warnedMissingBaseUrl = false;

  /// Logs [BackendFallbackLogger.logBackendBaseUrlMissingWarning] once per process when URL is unset.
  static void warnIfBackendBaseUrlMissing(String context) {
    const raw = String.fromEnvironment('BACKEND_ORDERS_BASE_URL', defaultValue: '');
    if (raw.trim().isEmpty) {
      debugPrint('[BackendConfig] WARNING: BACKEND_ORDERS_BASE_URL not set for flow: $context');
    }
    if (baseUrl.trim().isNotEmpty) return;
    if (_warnedMissingBaseUrl) return;
    _warnedMissingBaseUrl = true;
    BackendFallbackLogger.logBackendBaseUrlMissingWarning(context: context);
  }

  /// Deprecated: Firebase/catalog fallback removed — always false.
  static bool get shouldShowDevFirebaseFallbackBanner => false;

  /// Deprecated: hybrid fallback banners removed — always false.
  static bool get shouldShowBackendDevFallbackBanner => false;

  static void enforceStartupSafetyOrThrow() {
    if (stagingMode && baseUrl.trim().isEmpty) {
      throw StateError('STAGING_BACKEND_REQUIRED');
    }
    if (!kDebugMode && baseUrl.trim().isEmpty) {
      throw StateError(
        'BACKEND_ORDERS_BASE_URL must be configured in non-debug builds for hardened backend integration.',
      );
    }
  }

  /// Remote config can override rollout later by branching on the same predicate in one place.
  static bool shouldAttemptBackendPrimary({required String? uid, required String orderId}) {
    if (!useBackendOrdersRead) return false;
    if (baseUrl.trim().isEmpty) return false;
    var p = backendOrdersReadRolloutPercent;
    if (p <= 0 || p > 100) p = 100;
    if (p >= 100) return true;
    final h = '${uid ?? ''}|$orderId'.hashCode.abs() % 100;
    return h < p;
  }

  static bool shouldAttemptBackendWrite({required String? uid}) {
    if (!useBackendOrdersWrite) return false;
    if (baseUrl.trim().isEmpty) return false;
    var p = backendOrdersWriteRolloutPercent;
    if (p <= 0 || p > 100) p = 100;
    if (p >= 100) return true;
    final h = '${uid ?? ''}|order_write'.hashCode.abs() % 100;
    return h < p;
  }

  static bool get shouldRunDevConsistencyValidation => useBackendStoreReads || useBackendProductsReads;
}
