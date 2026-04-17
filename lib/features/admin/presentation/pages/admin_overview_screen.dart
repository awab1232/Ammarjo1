import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/admin_overview_metrics.dart';
import '../../data/admin_repository.dart';
import 'admin_order_detail_screen.dart';

/// لوحة مؤشرات تحليلية — استعلامات محدودة (≤100 وثيقة) + تجميعات count.
class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({super.key});

  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  late Future<AdminOverviewMetrics> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminRepository.instance.loadOverviewDashboard();
  }

  Future<void> _reload() async {
    setState(() {
      _future = AdminRepository.instance.loadOverviewDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminOverviewMetrics>(
      future: _future,
      builder: (context, snap) {
        try {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.orange));
          }
          if (snap.hasError) {
            debugPrint('[AdminOverview] FutureBuilder error: ${snap.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('تعذر تحميل النظرة العامة.', style: GoogleFonts.tajawal(color: AppColors.error)),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snap.data!;
          final wide = MediaQuery.sizeOf(context).width >= 760;

          return RefreshIndicator(
            color: AppColors.orange,
            onRefresh: () async => _reload(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final pad = 16.0;
                final kpis = _KpiRow(
                  wide: wide,
                  maxWidth: maxW,
                  data: data,
                );
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(pad),
                  children: [
                    kpis,
                    const SizedBox(height: 20),
                    Text('نشاط الطلبات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    _OrdersChartCard(
                      data: data,
                      wide: wide,
                    ),
                    const SizedBox(height: 24),
                    Text('أحدث الطلبات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...data.lastOrders.map((d) => _OrderTile(row: d)),
                    if (data.lastOrders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('لا طلبات.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                      ),
                    const SizedBox(height: 24),
                    Text('أحدث المستخدمين (عيّنة)', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...data.recentUsers.map((d) => _UserTile(row: d, onShowProfile: () => _showUserPeek(context, d))),
                    if (data.recentUsers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('لا مستخدمين.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                      ),
                  ],
                );
              },
            ),
          );
        } on Object {
          debugPrint('[AdminOverview] FutureBuilder render failed');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('حدث خطأ غير متوقع في لوحة المؤشرات.', style: GoogleFonts.tajawal(color: AppColors.error)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  void _showUserPeek(BuildContext context, Map<String, dynamic> m) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مستخدم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),
            SelectableText('المعرف: ${m['id'] ?? m['firebase_uid'] ?? '—'}', style: GoogleFonts.tajawal(fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText('البريد: ${m['email'] ?? '—'}', style: GoogleFonts.tajawal()),
            const SizedBox(height: 6),
            SelectableText('الهاتف: ${m['phone'] ?? '—'}', style: GoogleFonts.tajawal()),
            const SizedBox(height: 6),
            Text(
              'المحفظة: ${((m['wallet_balance'] as num?)?.toDouble() ?? 0).toStringAsFixed(3)} JD',
              style: GoogleFonts.tajawal(),
            ),
            const SizedBox(height: 16),
            Text(
              'للتعديل الكامل افتح قسم «المستخدمون» من القائمة.',
              style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.wide, required this.maxWidth, required this.data});

  final bool wide;
  final double maxWidth;
  final AdminOverviewMetrics data;

  @override
  Widget build(BuildContext context) {
    final commissionRate = 0.12;
    final commissionEarned = data.sampleOrdersRevenue * commissionRate;
    final storeEarnings = (data.sampleOrdersRevenue - commissionEarned) < 0
        ? 0.0
        : (data.sampleOrdersRevenue - commissionEarned);
    final children = [
      _KpiCard(
        title: 'إجمالي الطلبات',
        value: '${data.totalOrders}',
        icon: Icons.receipt_long_outlined,
        color: Colors.blue.shade700,
      ),
      _KpiCard(
        title: 'إجمالي المستخدمين',
        value: '${data.totalUsers}',
        icon: Icons.people_outline,
        color: AppColors.navy,
      ),
      _KpiCard(
        title: 'عمولات غير مسددة (تقريبي)',
        value: '${data.unpaidCommissions.toStringAsFixed(2)} د${data.commissionsTruncated ? '+' : ''}',
        icon: Icons.percent_outlined,
        color: Colors.orange.shade800,
        subtitle: data.commissionsTruncated ? 'من أول $kAdminOverviewCommissionsSample متجر' : null,
      ),
      _KpiCard(
        title: 'إيرادات الطلبات (عيّنة)',
        value: '${data.sampleOrdersRevenue.toStringAsFixed(2)} د.أ',
        icon: Icons.payments_outlined,
        color: Colors.green.shade700,
        subtitle:
            'مجموع قيم آخر $kAdminOverviewOrdersSample طلباً · متوسط ${data.avgOrderValue.toStringAsFixed(2)} د.أ',
      ),
      _KpiCard(
        title: 'عمولة المنصة المكتسبة',
        value: '${commissionEarned.toStringAsFixed(2)} د.أ',
        icon: Icons.trending_up_rounded,
        color: Colors.deepOrange.shade700,
        subtitle: 'حساب تقريبي بنسبة ${(commissionRate * 100).toStringAsFixed(0)}%',
      ),
      _KpiCard(
        title: 'أرباح المتاجر (تقديري)',
        value: '${storeEarnings.toStringAsFixed(2)} د.أ',
        icon: Icons.storefront_outlined,
        color: Colors.teal.shade700,
        subtitle: 'صافي إيراد المتاجر بعد عمولة المنصة',
      ),
    ];

    if (wide && maxWidth >= 900) {
      return GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: children,
      );
    }
    if (wide) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: children,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.w800, color: color),
              textAlign: TextAlign.right,
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: GoogleFonts.tajawal(fontSize: 10, color: AppColors.textSecondary),
                textAlign: TextAlign.right,
              ),
          ],
        ),
      ),
    );
  }
}

class _OrdersChartCard extends StatefulWidget {
  const _OrdersChartCard({required this.data, required this.wide});

  final AdminOverviewMetrics data;
  final bool wide;

  @override
  State<_OrdersChartCard> createState() => _OrdersChartCardState();
}

class _OrdersChartCardState extends State<_OrdersChartCard> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.chartMode == AdminChartMode.empty || data.chartPoints.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text(
            'لا توجد بيانات كافية بعد لعرض المخطط.',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < data.chartPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), data.chartPoints[i].value));
    }
    final maxY = spots.map((s) => s.y).fold<double>(1, (a, b) => a > b ? a : b);
    final chartH = widget.wide ? 220.0 : 180.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            data.chartMode == AdminChartMode.daily7 ? 'آخر 7 أيام' : 'آخر 5 أشهر (تقريبي)',
            style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.right,
          ),
          SizedBox(
            height: chartH,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (data.chartPoints.length - 1).toDouble(),
                minY: 0,
                maxY: maxY < 1 ? 5 : maxY * 1.2,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY < 1 ? 1 : null,
                  getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, m) => Text(
                        v.toInt().toString(),
                        style: GoogleFonts.tajawal(fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        if (i < 0 || i >= data.chartPoints.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            data.chartPoints[i].label,
                            style: GoogleFonts.tajawal(fontSize: 9, color: AppColors.textSecondary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.orange,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                        radius: _touched == i ? 6 : 4,
                        color: AppColors.orange,
                        strokeWidth: _touched == i ? 2 : 0,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.orange.withValues(alpha: 0.12),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touched) {
                      return touched.map((t) {
                        final i = t.x.toInt();
                        if (i < 0 || i >= data.chartPoints.length) {
                          return LineTooltipItem('', GoogleFonts.tajawal());
                        }
                        final p = data.chartPoints[i];
                        return LineTooltipItem(
                          '${p.label}\n${p.value.toInt()} طلب',
                          GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                  touchCallback: (FlTouchEvent e, LineTouchResponse? r) {
                    if (r?.lineBarSpots == null || r!.lineBarSpots!.isEmpty) {
                      setState(() => _touched = null);
                      return;
                    }
                    setState(() => _touched = r.lineBarSpots!.first.x.toInt());
                  },
                ),
              ),
            ),
          ),
          if (_touched != null && _touched! >= 0 && _touched! < data.chartPoints.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'المحدد: ${data.chartPoints[_touched!].label} — ${data.chartPoints[_touched!].value.toInt()} طلب',
                style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.darkOrange),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final oid = row['order_id']?.toString() ?? '';
    final payload = row['payload'];
    Map<String, dynamic>? pay;
    if (payload is Map) pay = Map<String, dynamic>.from(payload);
    final total = row['total_numeric']?.toString() ?? pay?['total']?.toString() ?? '—';
    final status = row['status']?.toString() ?? pay?['status']?.toString() ?? '';
    final short = oid.length > 8 ? oid.substring(0, 8) : oid;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          'طلب ${pay?['orderNumber'] ?? short}',
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('$total · $status', style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
        trailing: const Icon(Icons.chevron_left, color: AppColors.orange),
        onTap: () {
          if (oid.isEmpty) return;
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => AdminOrderDetailScreen(orderId: oid)),
          );
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.row, required this.onShowProfile});

  final Map<String, dynamic> row;
  final VoidCallback onShowProfile;

  @override
  Widget build(BuildContext context) {
    final m = row;
    final email = (m['email'] as String?)?.trim() ?? '';
    final idStr = m['id']?.toString() ?? m['firebase_uid']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          email.isNotEmpty ? email : idStr,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(m['phone']?.toString() ?? '—', style: GoogleFonts.tajawal(fontSize: 12)),
        trailing: TextButton(
          onPressed: onShowProfile,
          child: Text('تفاصيل', style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
