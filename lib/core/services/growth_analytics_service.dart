import 'package:flutter/foundation.dart' show debugPrint;

class GrowthAnalyticsService {
  GrowthAnalyticsService._();

  static final GrowthAnalyticsService instance = GrowthAnalyticsService._();

  final Map<String, DateTime> _eventDedup = <String, DateTime>{};

  void logEvent(
    String eventName, {
    Map<String, Object?> payload = const <String, Object?>{},
    String? dedupKey,
    Duration dedupWindow = const Duration(seconds: 20),
  }) {
    final key = dedupKey == null ? null : '$eventName::$dedupKey';
    if (key != null) {
      final previous = _eventDedup[key];
      final now = DateTime.now();
      if (previous != null && now.difference(previous) < dedupWindow) {
        return;
      }
      _eventDedup[key] = now;
    }
    debugPrint('[GrowthAnalytics] $eventName $payload');
  }
}
