import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesale_order_model.dart';

class WholesalerAnalyticsSection extends StatelessWidget {
  const WholesalerAnalyticsSection({super.key, required this.wholesalerId});
  final String wholesalerId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeatureState<List<WholesaleOrderModel>>>(
      future: WholesaleRepository.instance.getWholesalerIncomingOrders(wholesalerId),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
        final orders = switch (snap.data) {
          FeatureSuccess(:final data) => data,
          _ => <WholesaleOrderModel>[],
        };
        double totalSales = 0;
        double commission = 0;
        double net = 0;
        final byDay = <String, double>{};
        final productCount = <String, int>{};
        for (final o in orders) {
          totalSales += o.subtotal;
          commission += o.commission;
          net += o.netAmount;
          final key = '${o.createdAt.year}-${o.createdAt.month}-${o.createdAt.day}';
          byDay[key] = (byDay[key] ?? 0.0) + o.subtotal;
          for (final it in o.items) {
            productCount[it.name] = (productCount[it.name] ?? 0) + it.quantity;
          }
        }
        final entries = byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        final spots = <FlSpot>[];
        for (var i = 0; i < entries.length; i++) {
          spots.add(FlSpot(i.toDouble(), entries[i].value));
        }
        final topProducts = productCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(child: _kpi('إجمالي المبيعات', totalSales.toStringAsFixed(2))),
                const SizedBox(width: 8),
                Expanded(child: _kpi('عدد الطلبات', '${orders.length}')),
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
                    LineChartBarData(spots: spots, isCurved: true, color: Colors.green, dotData: const FlDotData(show: false)),
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
                    Text('أفضل منتجات تاجر الجملة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800), textAlign: TextAlign.right),
                    ...topProducts.take(10).map((e) => ListTile(
                          dense: true,
                          title: Text(e.key, textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
                          trailing: Text('${e.value}', style: GoogleFonts.tajawal()),
                        )),
                  ],
                ),
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
