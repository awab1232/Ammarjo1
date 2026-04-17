import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import '../../../../core/data/repositories/firebase_orders_repository.dart';

/// Periodic replay of Firebase mirror failures (non-blocking; no UI).
abstract final class FailedMirrorOrdersWorker {
  static Timer? _timer;

  static const Duration _period = Duration(minutes: 2);

  /// Same as [FirebaseOrdersRepository.dlqLockOwnerForInstance] — exposed for ops / admin.
  static String get lockOwner => FirebaseOrdersRepository.dlqLockOwnerForInstance;

  static void start() {
    if (!Firebase.apps.isNotEmpty) return;
    _timer?.cancel();
    _timer = Timer.periodic(_period, (_) {
      unawaited(FirebaseOrdersRepository.processFailedMirrorDlqBatch());
    });
    unawaited(FirebaseOrdersRepository.processFailedMirrorDlqBatch());
  }
}
