import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';

class AdminAnalyticsSection extends StatefulWidget {
  const AdminAnalyticsSection({super.key});

  @override
  State<AdminAnalyticsSection> createState() => _AdminAnalyticsSectionState();
}

class _AdminAnalyticsSectionState extends State<AdminAnalyticsSection> {
  DateTime _start = DateTime.now().subtract(const Duration(days: 29));
  DateTime _end = DateTime.now();
  int _loadKey = 0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AnalyticsSummary>(
      key: ValueKey<String>('analytics_${_start.toIso8601String()}_${_end.toIso8601String()}_$_loadKey'),
      future: AnalyticsService.instance.getDateRangeAnalytics(_start, _end),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
        }
        if (snap.hasError) {
          debugPrint('[AdminAnalyticsSection] load failed: ${snap.error}');
          if (snap.stackTrace != null) {
            debugPrintStack(stackTrace: snap.stackTrace);
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('تعذر تحميل التحليلات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => setState(() => _loadKey++),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
        }
        final data = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(child: _kpi('إجمالي المستخدمين', '${data.totalUsers}')),
                const SizedBox(width: 8),
                Expanded(child: _kpi('طلبات B2C', '${data.totalOrdersB2c}')),
                const SizedBox(width: 8),
                Expanded(child: _kpi('طلبات B2B', '${data.totalOrdersB2b}')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _kpi('الإيرادات', data.totalRevenue.toStringAsFixed(2))),
                const SizedBox(width: 8),
                Expanded(child: _kpi('العمولات', data.platformCommission.toStringAsFixed(2))),
                const SizedBox(width: 8),
                Expanded(child: _kpi('مستخدمون جدد', '${data.newUsers}')),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2023),
                        lastDate: DateTime.now(),
                        initialDate: _start,
                      );
                      if (d != null) setState(() => _start = d);
                    },
                    child: Text('من: ${_fmt(_start)}', style: GoogleFonts.tajawal()),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2023),
                        lastDate: DateTime.now(),
                        initialDate: _end,
                      );
                      if (d != null) setState(() => _end = d);
                    },
                    child: Text('إلى: ${_fmt(_end)}', style: GoogleFonts.tajawal()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _salesChart(data),
            const SizedBox(height: 12),
            _commissionChart(data),
            const SizedBox(height: 12),
            _topTable('أفضل المنتجات', data.topProducts, 'مبيعات'),
            _topTable('أفضل المتاجر', data.topStores, 'طلبات'),
            _topTable('أفضل تجار الجملة', data.topWholesalers, 'طلبات'),
          ],
        );
      },
    );
  }

  Widget _kpi(String t, String v) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text(t, style: GoogleFonts.tajawal(fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(v, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );

  Widget _salesChart(AnalyticsSummary data) {
    if (data.dailySeries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('لا بيانات يومية في النطاق المحدد.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
        ),
      );
    }
    final n = data.dailySeries.length;
    final pointsB2c = <FlSpot>[];
    final pointsB2b = <FlSpot>[];
    double maxY = 1;
    for (var i = 0; i < n; i++) {
      final b2c = data.dailySeries[i].b2cRevenue;
      final b2b = data.dailySeries[i].b2bRevenue;
      pointsB2c.add(FlSpot(i.toDouble(), b2c));
      pointsB2b.add(FlSpot(i.toDouble(), b2b));
      if (b2c > maxY) maxY = b2c;
      if (b2b > maxY) maxY = b2b;
    }
    // fl_chart يتطلب نقطتين على الأقل لخط المبيعات عند يوم واحد في النطاق
    if (n == 1) {
      pointsB2c.add(FlSpot(1, pointsB2c.first.y));
      pointsB2b.add(FlSpot(1, pointsB2b.first.y));
    }
    if (maxY <= 0) maxY = 1;
    final maxX = n <= 1 ? 1.0 : (n - 1).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: math.max(maxY * 1.15, 1),
              gridData: FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: pointsB2c,
                  isCurved: true,
                  color: Colors.blue,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: pointsB2b,
                  isCurved: true,
                  color: Colors.green,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _commissionChart(AnalyticsSummary data) {
    if (data.dailySeries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('لا بيانات عمولات يومية في النطاق.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
        ),
      );
    }
    final bars = <BarChartGroupData>[];
    double maxY = 1;
    for (var i = 0; i < data.dailySeries.length; i++) {
      final c = data.dailySeries[i].commission;
      if (c > maxY) maxY = c;
      bars.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: c, color: Colors.orange, width: 8)],
      ));
    }
    if (maxY <= 0) maxY = 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: math.max(maxY * 1.15, 1),
              alignment: BarChartAlignment.spaceAround,
              groupsSpace: 4,
              gridData: FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: bars,
            ),
          ),
        ),
      ),
    );
  }

  Widget _topTable(String title, List<AnalyticsTopRow> rows, String countLabel) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800), textAlign: TextAlign.right),
            const SizedBox(height: 8),
            ...rows.map(
              (r) => ListTile(
                dense: true,
                title: Text(r.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700), textAlign: TextAlign.right),
                subtitle: Text('$countLabel: ${r.count}', style: GoogleFonts.tajawal(fontSize: 12), textAlign: TextAlign.right),
                trailing: Text(r.revenue.toStringAsFixed(2), style: GoogleFonts.tajawal()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
