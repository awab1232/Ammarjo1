import 'package:flutter/foundation.dart' show debugPrint;

import 'backend_admin_client.dart';

const int kAdminOverviewOrdersSample = 55;
const int kAdminOverviewCommissionsSample = 40;
const int kAdminOverviewUsersSample = 5;

enum AdminChartMode { daily7, monthly5, empty }

class AdminChartPoint {
  AdminChartPoint({required this.label, required this.value, required this.rawDate});
  final String label;
  final double value;
  final DateTime rawDate;
}

/// Aggregates for [AdminOverviewScreen] — PostgreSQL via [BackendAdminClient].
class AdminOverviewMetrics {
  AdminOverviewMetrics({
    required this.totalOrders,
    required this.totalUsers,
    required this.unpaidCommissions,
    required this.avgOrderValue,
    required this.sampleOrdersRevenue,
    required this.chartMode,
    required this.chartPoints,
    required this.lastOrders,
    required this.recentUsers,
    required this.commissionsTruncated,
  });

  final int totalOrders;
  final int totalUsers;
  final double unpaidCommissions;
  final double avgOrderValue;
  final double sampleOrdersRevenue;
  final AdminChartMode chartMode;
  final List<AdminChartPoint> chartPoints;
  final List<Map<String, dynamic>> lastOrders;
  final List<Map<String, dynamic>> recentUsers;
  final bool commissionsTruncated;
}

class _ChartBuildResult {
  _ChartBuildResult({required this.points, required this.sufficient});
  final List<AdminChartPoint> points;
  final bool sufficient;
}

_ChartBuildResult _buildDailyBucketsLast7Days(List<Map<String, dynamic>> orderRows) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
  final keys = List.generate(7, (i) => start.add(Duration(days: i)));
  final counts = <String, int>{for (final k in keys) '${k.year}-${k.month}-${k.day}': 0};

  var withDate = 0;
  for (final m in orderRows) {
    final t = m['created_at'];
    DateTime? dt;
    if (t is String) {
      dt = DateTime.tryParse(t);
    }
    if (dt == null) continue;
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day.isBefore(start) || day.isAfter(keys.last.add(const Duration(days: 1)))) continue;
    final key = '${day.year}-${day.month}-${day.day}';
    if (counts.containsKey(key)) {
      counts[key] = (counts[key] ?? 0) + 1;
      withDate++;
    }
  }
  final points = <AdminChartPoint>[];
  for (final k in keys) {
    final key = '${k.year}-${k.month}-${k.day}';
    points.add(AdminChartPoint(label: '${k.day}/${k.month}', value: (counts[key] ?? 0).toDouble(), rawDate: k));
  }
  final nonZero = points.where((p) => p.value > 0).length;
  final sufficient = nonZero >= 1 && withDate >= 1;
  return _ChartBuildResult(points: points, sufficient: sufficient);
}

_ChartBuildResult _buildMonthlyBucketsLast5Months(List<Map<String, dynamic>> orderRows) {
  final now = DateTime.now();
  final months = <DateTime>[];
  for (var i = 0; i < 5; i++) {
    final m = DateTime(now.year, now.month - i, 1);
    months.add(m);
  }
  months.sort((a, b) => a.compareTo(b));
  final counts = <String, int>{for (final m in months) '${m.year}-${m.month}': 0};

  for (final m in orderRows) {
    final t = m['created_at'];
    DateTime? dt;
    if (t is String) {
      dt = DateTime.tryParse(t);
    }
    if (dt == null) continue;
    final key = '${dt.year}-${dt.month}';
    if (counts.containsKey(key)) {
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final points = <AdminChartPoint>[];
  for (final m in months) {
    final key = '${m.year}-${m.month}';
    points.add(
      AdminChartPoint(
        label: '${m.month}/${m.year}',
        value: (counts[key] ?? 0).toDouble(),
        rawDate: m,
      ),
    );
  }
  final nonZero = points.where((p) => p.value > 0).length;
  return _ChartBuildResult(points: points, sufficient: nonZero >= 1);
}

/// Loads dashboard KPIs from `/admin/rest/*`.
Future<AdminOverviewMetrics> loadAdminOverviewMetrics() async {
  try {
    final o = await BackendAdminClient.instance.fetchOverview();
    final fin = await BackendAdminClient.instance.fetchFinance();
    final ord = await BackendAdminClient.instance.fetchOrders(limit: kAdminOverviewOrdersSample, offset: 0);
    final usr = await BackendAdminClient.instance.fetchUsers(limit: kAdminOverviewUsersSample, offset: 0);

    final totalOrders = (o?['orders_count'] as num?)?.toInt() ?? 0;
    final totalUsers = (o?['users_count'] as num?)?.toInt() ?? 0;
    final unpaidCommissions = (fin?['outstanding_balance'] as num?)?.toDouble() ?? 0;

    final orderItems = ord?['items'];
    final orderRows = <Map<String, dynamic>>[];
    if (orderItems is List) {
      for (final e in orderItems) {
        if (e is Map) orderRows.add(Map<String, dynamic>.from(e));
      }
    }

    final totalsForAvg = <double>[];
    var sampleOrdersRevenue = 0.0;
    for (final m in orderRows) {
      final tn = (m['total_numeric'] as num?)?.toDouble();
      if (tn != null && tn > 0) {
        totalsForAvg.add(tn);
        sampleOrdersRevenue += tn;
      }
    }
    final avgOrder = totalsForAvg.isEmpty
        ? 0.0
        : totalsForAvg.reduce((a, b) => a + b) / totalsForAvg.length;

    final last5Orders = orderRows.take(5).toList();

    final userItems = usr?['items'];
    final recentUsers = <Map<String, dynamic>>[];
    if (userItems is List) {
      for (final e in userItems) {
        if (e is Map) recentUsers.add(Map<String, dynamic>.from(e));
      }
    }

    final chartDaily = _buildDailyBucketsLast7Days(orderRows);
    AdminChartMode chartMode = AdminChartMode.daily7;
    List<AdminChartPoint> chartPoints = chartDaily.points;
    if (!chartDaily.sufficient) {
      final monthly = _buildMonthlyBucketsLast5Months(orderRows);
      if (monthly.sufficient) {
        chartMode = AdminChartMode.monthly5;
        chartPoints = monthly.points;
      } else {
        chartMode = AdminChartMode.empty;
        chartPoints = [];
      }
    }

    return AdminOverviewMetrics(
      totalOrders: totalOrders,
      totalUsers: totalUsers,
      unpaidCommissions: unpaidCommissions,
      avgOrderValue: avgOrder,
      sampleOrdersRevenue: sampleOrdersRevenue,
      chartMode: chartMode,
      chartPoints: chartPoints,
      lastOrders: last5Orders,
      recentUsers: recentUsers,
      commissionsTruncated: orderRows.length >= kAdminOverviewCommissionsSample,
    );
  } on Object {
    debugPrint('[AdminOverviewMetrics] load failed');
    return AdminOverviewMetrics(
      totalOrders: 0,
      totalUsers: 0,
      unpaidCommissions: 0,
      avgOrderValue: 0,
      sampleOrdersRevenue: 0,
      chartMode: AdminChartMode.empty,
      chartPoints: [],
      lastOrders: [],
      recentUsers: [],
      commissionsTruncated: false,
    );
  }
}
