import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// In-memory counters for write cutover paths (no UI; debug logs optional).
abstract final class OrderWriteCutoverMetrics {
  static int _backendOkFirebaseMirrorFailAfterRetries = 0;
  static int _backendFailFirebaseOk = 0;
  static int _backendOkFirebaseMirrorOk = 0;

  static int _dlqEnqueued = 0;
  static int _dlqPendingApprox = 0;
  static int _dlqReplaySuccess = 0;
  static int _dlqReplayFailure = 0;
  static int _dlqDeadLettered = 0;

  static void recordBackendPrimaryMirrorSucceeded() {
    _backendOkFirebaseMirrorOk++;
  }

  static void recordBackendPrimaryMirrorExhausted() {
    _backendOkFirebaseMirrorFailAfterRetries++;
    if (kDebugMode) {
      debugPrint('[OrderWriteCutoverMetrics] mirror exhausted (see snapshot)');
    }
  }

  static void recordBackendFailedFirebaseSucceeded() {
    _backendFailFirebaseOk++;
  }

  static void recordDlqEnqueued() {
    _dlqEnqueued++;
    _dlqPendingApprox++;
  }

  static void recordDlqReplaySuccess() {
    _dlqReplaySuccess++;
    if (_dlqPendingApprox > 0) {
      _dlqPendingApprox--;
    }
  }

  static void recordDlqReplayFailure() {
    _dlqReplayFailure++;
  }

  static void recordDlqDeadLettered() {
    _dlqDeadLettered++;
    if (_dlqPendingApprox > 0) {
      _dlqPendingApprox--;
    }
  }

  static int get dlqEnqueuedTotal => _dlqEnqueued;

  static int get dlqReplaySuccessTotal => _dlqReplaySuccess;

  static int get dlqReplayFailureTotal => _dlqReplayFailure;

  static int get dlqDeadLetteredTotal => _dlqDeadLettered;

  /// Replay successes / (successes + failures) since process start; 0 if none.
  static double get dlqReplaySuccessRate {
    final d = _dlqReplaySuccess + _dlqReplayFailure;
    if (d == 0) return 0;
    return _dlqReplaySuccess / d;
  }

  static Map<String, dynamic> get snapshot => <String, dynamic>{
        'backendOk_firebaseMirrorOk': _backendOkFirebaseMirrorOk,
        'backendOk_firebaseMirrorFailAfterRetries': _backendOkFirebaseMirrorFailAfterRetries,
        'backendFail_firebaseOk': _backendFailFirebaseOk,
        'dlqEnqueuedTotal': _dlqEnqueued,
        'dlqPendingApprox': _dlqPendingApprox,
        'dlqReplaySuccessTotal': _dlqReplaySuccess,
        'dlqReplayFailureTotal': _dlqReplayFailure,
        'dlqDeadLetteredTotal': _dlqDeadLettered,
        'dlqReplaySuccessRate': dlqReplaySuccessRate,
      };
}
