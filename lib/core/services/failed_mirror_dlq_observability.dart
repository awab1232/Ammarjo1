import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'order_write_cutover_metrics.dart';

/// Thresholds and hooks for DLQ production observability (non-blocking; no UI).
///
/// Set [onAlert] to forward to Crashlytics, remote logging, or PagerDuty.
abstract final class FailedMirrorDlqObservability {
  /// When total dead-letter count in this process reaches or exceeds this value, fire [onAlert]. `0` = disabled.
  static int alertDeadLetterTotalThreshold = 0;

  /// When session replay success rate falls strictly below this (after [alertMinReplaysForRate] replays), fire [onAlert]. `0` = disabled.
  static double alertReplaySuccessRateMin = 0;

  /// Minimum `(success + failure)` replay attempts before evaluating [alertReplaySuccessRateMin].
  static int alertMinReplaysForRate = 10;

  /// Optional batch-window check: if a single [processFailedMirrorDlqBatch] has at least this many replay attempts and rate is below [alertBatchReplaySuccessRateMin], alert. `0` = disabled.
  static int alertMinBatchReplaysForRate = 3;

  static double alertBatchReplaySuccessRateMin = 0.5;

  /// Invoked on threshold breach (keep synchronous and fast; schedule async work yourself).
  static void Function(String code, String message, Map<String, dynamic> context)? onAlert;

  static void _emit(String code, String message, Map<String, dynamic> context) {
    if (kDebugMode) {
      debugPrint('[DLQ_ALERT] $code: $message $context');
    }
    try {
      onAlert?.call(code, message, context);
    } on Object {
      debugPrint('FailedMirrorDlqObservability.onAlert failed: unexpected error\n$StackTrace.current');
    }
  }

  static void evaluateDeadLetterTotalAfterIncrement() {
    final t = alertDeadLetterTotalThreshold;
    if (t <= 0) return;
    final n = OrderWriteCutoverMetrics.dlqDeadLetteredTotal;
    if (n >= t) {
      _emit(
        'dlq_dead_letter_threshold',
        'Dead-letter count reached threshold',
        <String, dynamic>{
          'deadLetterTotal': n,
          'threshold': t,
        },
      );
    }
  }

  static void evaluateSessionReplaySuccessRate() {
    final minRate = alertReplaySuccessRateMin;
    if (minRate <= 0) return;
    final minN = alertMinReplaysForRate;
    if (minN <= 0) return;
    final s = OrderWriteCutoverMetrics.dlqReplaySuccessTotal;
    final f = OrderWriteCutoverMetrics.dlqReplayFailureTotal;
    final total = s + f;
    if (total < minN) return;
    final rate = OrderWriteCutoverMetrics.dlqReplaySuccessRate;
    if (rate < minRate) {
      _emit(
        'dlq_replay_success_rate_low',
        'Session DLQ replay success rate below minimum',
        <String, dynamic>{
          'replaySuccessRate': rate,
          'minRate': minRate,
          'replaySuccessTotal': s,
          'replayFailureTotal': f,
        },
      );
    }
  }

  static void evaluateBatchReplayRate({required int batchSuccesses, required int batchFailures}) {
    final minRate = alertBatchReplaySuccessRateMin;
    if (minRate <= 0) return;
    final minBatch = alertMinBatchReplaysForRate;
    if (minBatch <= 0) return;
    final total = batchSuccesses + batchFailures;
    if (total < minBatch) return;
    final rate = batchSuccesses / total;
    if (rate < minRate) {
      _emit(
        'dlq_batch_replay_success_rate_low',
        'Batch DLQ replay success rate below minimum',
        <String, dynamic>{
          'batchReplayRate': rate,
          'minRate': minRate,
          'batchSuccesses': batchSuccesses,
          'batchFailures': batchFailures,
        },
      );
    }
  }
}

