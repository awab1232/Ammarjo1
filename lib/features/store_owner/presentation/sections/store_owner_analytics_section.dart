import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/owner_entity_doc.dart';
import '../../data/store_owner_repository.dart';

class StoreOwnerAnalyticsSection extends StatelessWidget {
  const StoreOwnerAnalyticsSection({super.key, required this.storeId});
  final String storeId;

  static DateTime? _parseCreatedAt(dynamic created) {
    if (created is String) return DateTime.tryParse(created);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OwnerEntityDoc>>(
      future: StoreOwnerRepository.fetchStoreOrdersForAnalytics(storeId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('تعذّر تحميل الطلبات', textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textPrimary)),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
        }
        final docs = snap.data ?? const <OwnerEntityDoc>[];
        double sales = 0;
        final byDay = <String, double>{};
        final productCount = <String, int>{};
        for (final d in docs) {
          final m = d.data();
          final total = (m['totalNumeric'] is num)
              ? (m['totalNumeric'] as num).toDouble()
              : double.tryParse((m['total'] ?? '0').toString()) ?? 0.0;
          sales += total;
          final created = m['createdAt'];
          final dt = _parseCreatedAt(created);
          if (dt != null) {
            final key = '${dt.year}-${dt.month}-${dt.day}';
            byDay[key] = (byDay[key] ?? 0.0) + total;
          }
          final items = m['items'];
          if (items is List) {
            for (final item in items) {
              if (item is Map) {
                final name = (item['name'] ?? '').toString();
                final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 0;
                if (name.isNotEmpty) productCount[name] = (productCount[name] ?? 0) + qty;
              }
            }
          }
        }
        final avg = docs.isEmpty ? 0.0 : sales / docs.length;
        final commission = sales * 0.10;
        final net = sales - commission;
        final topProducts = productCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        final points = byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        final chartSpots = <FlSpot>[];
        for (var i = 0; i < points.length; i++) {
          chartSpots.add(FlSpot(i.toDouble(), points[i].value));
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(child: _kpi('إجمالي المبيعات', sales.toStringAsFixed(2))),
                const SizedBox(width: 8),
                Expanded(child: _kpi('عدد الطلبات', '${docs.length}')),
                const SizedBox(width: 8),
                Expanded(child: _kpi('متوسط الطلب', avg.toStringAsFixed(2))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _kpi('العمولة', commission.toStringAsFixed(2))),
                const SizedBox(width: 8),
                Expanded(child: _kpi('الصافي', net.toStringAsFixed(2))),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 220,
                  child: LineChart(LineChartData(lineBarsData: [
                    LineChartBarData(spots: chartSpots, color: Colors.blue, isCurved: true, dotData: const FlDotData(show: false)),
                  ])),
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('أفضل منتجات المتجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800), textAlign: TextAlign.right),
                    ...topProducts.take(10).map((e) => ListTile(
                          dense: true,
                          title: Text(e.key, textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
                          trailing: Text('${e.value}', style: GoogleFonts.tajawal()),
                        )),
                  ],
                ),
              ),
            ),
            Card(
              child: ListTile(
                title: Text('تقرير العمولات الشهرية', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                subtitle: Text('إجمالي العمولة المتوقعة: ${commission.toStringAsFixed(2)}', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpi(String t, String v) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [Text(t, style: GoogleFonts.tajawal(fontSize: 12)), const SizedBox(height: 4), Text(v, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800))]),
        ),
      );
}
