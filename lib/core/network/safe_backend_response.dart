import 'package:flutter/foundation.dart' show debugPrint;

/// Standard wrapper for optional backend data without throwing from repositories.
class SafeBackendResponse<T> {
  const SafeBackendResponse({
    this.data,
    this.success = true,
    this.error,
  });

  final T? data;
  final bool success;
  final String? error;

  static SafeBackendResponse<T> ok<T>(T data) => SafeBackendResponse<T>(data: data, success: true);

  static SafeBackendResponse<T> fail<T>(String message, [T? data]) =>
      SafeBackendResponse<T>(data: data, success: false, error: message);
}

void logWarning(String message) {
  debugPrint('[BackendWarning] $message');
}
