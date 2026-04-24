import '../logging/backend_fallback_logger.dart';
import 'backend_orders_client.dart';

class AnalyticsTopRow {
  const AnalyticsTopRow({
    required this.id,
    required this.name,
    required this.count,
    required this.revenue,
  });

  final String id;
  final String name;
  final int count;
  final double revenue;
}

class DailySeriesPoint {
  const DailySeriesPoint({
    required this.day,
    required this.b2cRevenue,
    required this.b2bRevenue,
    required this.commission,
  });

  final DateTime day;
  final double b2cRevenue;
  final double b2bRevenue;
  final double commission;
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalUsers,
    required this.newUsers,
    required this.totalOrdersB2c,
    required this.totalOrdersB2b,
    required this.totalRevenue,
    required this.platformCommission,
    required this.topProducts,
    required this.topStores,
    required this.topWholesalers,
    required this.dailySeries,
  });

  final int totalUsers;
  final int newUsers;
  final int totalOrdersB2c;
  final int totalOrdersB2b;
  final double totalRevenue;
  final double platformCommission;
  final List<AnalyticsTopRow> topProducts;
  final List<AnalyticsTopRow> topStores;
  final List<AnalyticsTopRow> topWholesalers;
  final List<DailySeriesPoint> dailySeries;
}

class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  Future<Map<String, dynamic>> getDailyAnalytics(DateTime date) async {
    final days = DateTime.now().difference(DateTime(date.year, date.month, date.day)).inDays.abs() + 1;
    final timeline = await BackendOrdersClient.instance.fetchAnalyticsDaily(days: days);
    if (timeline == null) return <String, dynamic>{};
    final key = _dayKey(date);
    for (final row in timeline) {
      final dayRaw = row['day']?.toString();
      if (dayRaw == null || dayRaw.isEmpty) continue;
      if (dayRaw == key) return row;
    }
    return <String, dynamic>{};
  }

  Future<AnalyticsSummary> getDateRangeAnalytics(DateTime start, DateTime end) async {
    final startUtc = DateTime(start.year, start.month, start.day);
    final endUtc = DateTime(end.year, end.month, end.day);
    final daysRange = endUtc.difference(startUtc).inDays.abs() + 1;
    final summary = await BackendOrdersClient.instance.fetchAnalyticsOverview();
    final timeline = await BackendOrdersClient.instance.fetchAnalyticsDaily(days: daysRange);
    final stores = await BackendOrdersClient.instance.fetchAnalyticsStores(limit: 10);
    final revenue = await BackendOrdersClient.instance.fetchAnalyticsRevenue(limit: 50);

    if (summary == null || timeline == null) {
      BackendFallbackLogger.logBackendFailureNoFallback(
        flow: 'analytics_backend',
        reason: 'missing_backend_analytics_response',
      );
      throw StateError('FIRESTORE_SHUTDOWN_PHASE_ACTIVE');
    }

    final daily = <DailySeriesPoint>[];
    for (final row in timeline) {
      final dayRaw = row['day']?.toString();
      if (dayRaw == null || dayRaw.isEmpty) {
        throw StateError('unexpected_empty_response');
      }
      final parsed = DateTime.tryParse(dayRaw);
      if (parsed == null) {
        throw StateError('INVALID_RESPONSE_FORMAT');
      }
      daily.add(
        DailySeriesPoint(
          day: DateTime(parsed.year, parsed.month, parsed.day),
          b2cRevenue: 0,
          b2bRevenue: 0,
          commission: 0,
        ),
      );
    }

    return AnalyticsSummary(
      totalUsers: 0,
      newUsers: 0,
      totalOrdersB2c: (summary['totalOrders'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA')),
      totalOrdersB2b: 0,
      totalRevenue: 0,
      platformCommission: 0,
      topProducts: const <AnalyticsTopRow>[],
      topStores: (stores ?? const <Map<String, dynamic>>[])
          .map(
            (r) => AnalyticsTopRow(
              id: r['technicianId']?.toString() ?? (throw StateError('unexpected_empty_response')),
              name: r['technicianId']?.toString() ?? (throw StateError('unexpected_empty_response')),
              count: (r['completed_jobs'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA')),
              revenue: (r['score'] as num?)?.toDouble() ?? (throw StateError('INVALID_NUMERIC_DATA')),
            ),
          )
          .toList(),
      topWholesalers: (revenue ?? const <Map<String, dynamic>>[])
          .map(
            (r) => AnalyticsTopRow(
              id: r['requestId']?.toString() ?? (throw StateError('unexpected_empty_response')),
              name: r['technicianId']?.toString() ?? (throw StateError('unexpected_empty_response')),
              count: 1,
              revenue: (r['durationHours'] as num?)?.toDouble() ?? (throw StateError('INVALID_NUMERIC_DATA')),
            ),
          )
          .toList(),
      dailySeries: daily,
    );
  }

  Future<void> updateDailyAnalytics() async {
    // Analytics persistence moved to backend ownership (PostgreSQL).
    final now = DateTime.now();
    await getDateRangeAnalytics(now, now);
  }

  String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
