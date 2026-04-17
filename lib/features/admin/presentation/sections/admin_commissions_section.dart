import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/admin_list_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/backend_admin_client.dart';
import '../widgets/admin_list_widgets.dart';

/// عمولات المتاجر — لقطة من `/stores/:storeId/commissions` + تسجيل دفعة عبر REST.
class AdminCommissionsSection extends StatefulWidget {
  const AdminCommissionsSection({super.key});

  @override
  State<AdminCommissionsSection> createState() => _AdminCommissionsSectionState();
}

class _AdminCommissionsSectionState extends State<AdminCommissionsSection> {
  final List<Map<String, dynamic>> _stores = [];
  int? _nextOffset;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _stores.clear();
      _nextOffset = null;
    });
    try {
      final res = await BackendAdminClient.instance.fetchStores(limit: AdminListConstants.pageSize, offset: 0);
      _applyStorePage(res);
    } on Object {
      if (mounted) setState(() => _error = StateError('Failed to load commissions.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyStorePage(Map<String, dynamic>? res) {
    final items = res?['items'];
    if (items is List) {
      for (final e in items) {
        if (e is Map) _stores.add(Map<String, dynamic>.from(e));
      }
    }
    _nextOffset = (res?['nextOffset'] as num?)?.toInt();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _nextOffset == null) return;
    setState(() => _loadingMore = true);
    try {
      final res = await BackendAdminClient.instance.fetchStores(
        limit: AdminListConstants.pageSize,
        offset: _nextOffset!,
      );
      if (mounted) setState(() => _applyStorePage(res));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AdminListShimmer();
    if (_error != null) {
      return AdminErrorRetryBody(onRetry: _refresh);
    }
    if (_stores.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('لا متاجر.', textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('تحديث', style: GoogleFonts.tajawal()),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _stores.length + (_nextOffset != null ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i >= _stores.length) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator(color: AppColors.orange)
                          : TextButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more_rounded),
                              label: Text('تحميل المزيد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                            ),
                    ),
                  );
                }
                final row = _stores[i];
                final storeId = row['id']?.toString() ?? '';
                final name = row['name']?.toString().trim();
                return _StoreCommissionTile(
                  storeId: storeId,
                  title: (name != null && name.isNotEmpty) ? name : storeId,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _StoreCommissionTile extends StatefulWidget {
  const _StoreCommissionTile({required this.storeId, required this.title});

  final String storeId;
  final String title;

  @override
  State<_StoreCommissionTile> createState() => _StoreCommissionTileState();
}

class _StoreCommissionTileState extends State<_StoreCommissionTile> {
  Future<Map<String, dynamic>?>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = BackendAdminClient.instance.fetchStoreCommissionsSnapshot(widget.storeId);
    });
  }

  Future<void> _recordPayment(BuildContext context, double balance) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تسجيل دفعة', style: GoogleFonts.tajawal()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('المبلغ المستحق: ${balance.toStringAsFixed(2)} د', style: GoogleFonts.tajawal()),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ المدفوع',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'ملاحظة (محلية فقط)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orange),
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) return;
              final res = await BackendAdminClient.instance.postStoreCommissionPayment(widget.storeId, amount);
              if (res == null) return;
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم تسجيل الدفعة ✅', style: GoogleFonts.tajawal()),
                    backgroundColor: Colors.green,
                  ),
                );
                _reload();
              }
            },
            child: Text('حفظ', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData && snap.connectionState != ConnectionState.done) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(title: Text(widget.title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold))),
          );
        }
        final data = snap.data;
        final totalComm = (data?['totalCommission'] as num?)?.toDouble() ?? 0;
        final totalPaid = (data?['totalPaid'] as num?)?.toDouble() ?? 0;
        final balance = (data?['balance'] as num?)?.toDouble() ?? 0;
        final orders = data?['orders'];
        final orderList = orders is List ? orders : const [];
        var salesSum = 0.0;
        for (final o in orderList) {
          if (o is Map) {
            salesSum += (o['orderTotal'] as num?)?.toDouble() ?? 0;
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            title: Text(widget.title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'المستحق: ${balance.toStringAsFixed(2)} د',
                    style: GoogleFonts.tajawal(
                      color: balance > 0 ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _summaryCard('إجمالي المبيعات (طلبات مسجلة)', '${salesSum.toStringAsFixed(2)} د', Colors.blue)),
                        const SizedBox(width: 8),
                        Expanded(child: _summaryCard('العمولة', '${totalComm.toStringAsFixed(2)} د', AppColors.orange)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _summaryCard('المدفوع', '${totalPaid.toStringAsFixed(2)} د', Colors.green)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _summaryCard(
                            'المتبقي',
                            '${balance.toStringAsFixed(2)} د',
                            balance > 0 ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.payment),
                      label: Text('تسجيل دفعة', style: GoogleFonts.tajawal()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      onPressed: () => _recordPayment(context, balance),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('طلبات مسجلة للعمولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: orderList.length,
                      itemBuilder: (ctx, j) {
                        final o = orderList[j];
                        if (o is! Map) return const SizedBox.shrink();
                        final oid = o['orderId']?.toString() ?? '';
                        final shortId = oid.length > 8 ? oid.substring(0, 8) : oid;
                        final orderTotal = (o['orderTotal'] as num?)?.toDouble() ?? 0.0;
                        final comm = (o['commissionAmount'] as num?)?.toDouble() ?? 0.0;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.receipt_outlined, color: AppColors.orange),
                          title: Text('طلب #$shortId', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                          subtitle: Text('قيمة: ${orderTotal.toStringAsFixed(2)} د', style: GoogleFonts.tajawal(fontSize: 12)),
                          trailing: Text('${comm.toStringAsFixed(2)} د', style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'عمولات المناقصات وسجل الدفعات التفصيلي يُدار من الخادم.',
                      style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.tajawal(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(title, style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
