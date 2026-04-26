import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/admin_list_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/backend_admin_client.dart';
import 'admin_commission_per_category_section.dart';
import '../widgets/admin_list_widgets.dart';

/// عمولات المتاجر — لقطة من `/stores/:storeId/commissions` + تسجيل دفعة عبر REST.
class AdminCommissionsSection extends StatefulWidget {
  const AdminCommissionsSection({super.key});

  @override
  State<AdminCommissionsSection> createState() =>
      _AdminCommissionsSectionState();
}

class _AdminCommissionsSectionState extends State<AdminCommissionsSection>
    with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _stores = List<Map<String, dynamic>>.empty(
    growable: true,
  );
  final TextEditingController _searchCtrl = TextEditingController();
  int? _nextOffset;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  late final TabController _tabs;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _stores.clear();
      _nextOffset = null;
    });
    try {
      final res = await BackendAdminClient.instance.fetchStores(
        limit: AdminListConstants.pageSize,
        offset: 0,
      );
      _applyStorePage(res);
    } on Object {
      if (mounted) {
        setState(() => _error = StateError('Failed to load commissions.'));
      }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.orange,
            tabs: [
              Tab(child: Text('نظرة عامة', style: GoogleFonts.tajawal())),
              Tab(
                child: Text('العمولات بالتفصيل', style: GoogleFonts.tajawal()),
              ),
              Tab(
                child: Text(
                  'نسب العمولة بالتصنيف',
                  style: GoogleFonts.tajawal(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildOverviewTab(),
              _buildDetailsTab(),
              const AdminCommissionPerCategorySection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    if (_loading) return const AdminListShimmer();
    if (_error != null) return AdminErrorRetryBody(onRetry: _refresh);
    double total = 0;
    for (final s in _stores) {
      total += (s['commissionPercent'] as num?)?.toDouble() ?? 0;
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statCard(
            'إجمالي العمولات المستحقة',
            '${total.toStringAsFixed(2)} %',
          ),
          _statCard('إجمالي المدفوع', '—'),
          _statCard('إجمالي المتبقي', '—'),
          _statCard('عدد المتاجر المتأخرة', '${_stores.length}'),
        ],
      ),
    );
  }

  Widget _buildDetailsTab() {
    if (_loading) return const AdminListShimmer();
    if (_error != null) return AdminErrorRetryBody(onRetry: _refresh);
    final filtered = _stores.where((e) {
      final q = _query.trim().toLowerCase();
      if (q.isEmpty) return true;
      return (e['name']?.toString().toLowerCase() ?? '').contains(q);
    }).toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'لا متاجر.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length + 1 + (_nextOffset != null ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'بحث باسم المتجر',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            );
          }
          final idx = i - 1;
          if (idx >= filtered.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(color: AppColors.orange)
                    : TextButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          'تحميل المزيد',
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            );
          }
          final row = filtered[idx];
          final storeId = row['id']?.toString() ?? '';
          final name = row['name']?.toString().trim();
          return _StoreCommissionTile(
            storeId: storeId,
            title: (name != null && name.isNotEmpty) ? name : storeId,
          );
        },
      ),
    );
  }

  Widget _statCard(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(
          title,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
        trailing: Text(
          value,
          style: GoogleFonts.tajawal(
            fontWeight: FontWeight.w800,
            color: AppColors.orange,
          ),
        ),
      ),
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
  final TextEditingController _commissionPctCtrl = TextEditingController();
  bool _commissionPatchUnsupported = false;
  bool _commissionPctSaving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _commissionPctCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = BackendAdminClient.instance.fetchStoreCommissionsSnapshot(
        widget.storeId,
      );
    });
  }

  Future<void> _saveCommissionPercent(BuildContext context) async {
    final raw = _commissionPctCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('أدخل نسبة بين 0 و 100', style: GoogleFonts.tajawal()),
        ),
      );
      return;
    }
    final v = double.tryParse(raw.replaceAll(',', '.'));
    if (v == null || v < 0 || v > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'القيمة يجب أن تكون رقماً بين 0 و 100',
            style: GoogleFonts.tajawal(),
          ),
        ),
      );
      return;
    }
    setState(() => _commissionPctSaving = true);
    try {
      final r = await BackendAdminClient.instance
          .patchAdminStoreCommissionPercent(widget.storeId, v);
      if (!context.mounted) return;
      switch (r) {
        case AdminStoreCommissionPercentPatchResult.saved:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم حفظ نسبة العمولة',
                style: GoogleFonts.tajawal(),
              ),
              backgroundColor: Colors.green,
            ),
          );
          break;
        case AdminStoreCommissionPercentPatchResult.notSupported:
          setState(() => _commissionPatchUnsupported = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'الميزة غير مدعومة حالياً في الخادم',
                style: GoogleFonts.tajawal(),
              ),
            ),
          );
          break;
        case AdminStoreCommissionPercentPatchResult.failed:
          // ignore: avoid_print
          print(
            'ERROR TRIGGER LOCATION: admin_commissions_section _saveCommissionPercent failed result',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تعذر الحفظ. تحقق من الصلاحيات أو حاول لاحقاً.',
                style: GoogleFonts.tajawal(),
              ),
            ),
          );
          break;
      }
    } finally {
      if (mounted) setState(() => _commissionPctSaving = false);
    }
  }

  Future<void> _recordPayment(
    BuildContext context, {
    required double totalComm,
    required double totalPaid,
    required double balance,
  }) async {
    final amountController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تسجيل دفعة',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'المتجر: ${widget.title}',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(),
            ),
            const SizedBox(height: 6),
            Text(
              'إجمالي المستحق: ${totalComm.toStringAsFixed(2)} د',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(),
            ),
            Text(
              'المبلغ المدفوع: ${totalPaid.toStringAsFixed(2)} د',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(),
            ),
            Text(
              'المتبقي: ${balance.toStringAsFixed(2)} د',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(
                fontWeight: FontWeight.w700,
                color: balance > 0 ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'مبلغ الدفعة',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              onPressed: () async {
                final amount = double.tryParse(
                  amountController.text.trim().replaceAll(',', '.'),
                );
                if (amount == null || amount <= 0) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'أدخل مبلغاً صحيحاً',
                        style: GoogleFonts.tajawal(),
                      ),
                    ),
                  );
                  return;
                }
                final res = await BackendAdminClient.instance
                    .postStoreCommissionPayment(widget.storeId, amount);
                if (!mounted) return;
                if (res == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'تعذر تسجيل الدفعة',
                        style: GoogleFonts.tajawal(),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'تم تسجيل الدفعة',
                      style: GoogleFonts.tajawal(),
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
                _reload();
              },
              child: Text(
                'تأكيد تسجيل الدفعة',
                style: GoogleFonts.tajawal(color: Colors.white),
              ),
            ),
          ],
        ),
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
            child: ListTile(
              title: Text(
                widget.title,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        final data = snap.data;
        final totalComm = (data?['totalCommission'] as num?)?.toDouble() ?? 0;
        final totalPaid = (data?['totalPaid'] as num?)?.toDouble() ?? 0;
        final balance = (data?['balance'] as num?)?.toDouble() ?? 0;
        final orders = data?['orders'];
        final orderList = orders is List
            ? List<dynamic>.from(orders)
            : List<dynamic>.empty(growable: true);
        var salesSum = 0.0;
        for (final o in orderList) {
          if (o is Map) {
            salesSum += (o['orderTotal'] as num?)?.toDouble() ?? 0;
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ExpansionTile(
            title: Text(
              widget.title,
              style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: balance > 0
                        ? Colors.red.shade50
                        : Colors.green.shade50,
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
                        Expanded(
                          child: _summaryCard(
                            'إجمالي المبيعات (طلبات مسجلة)',
                            '${salesSum.toStringAsFixed(2)} د',
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _summaryCard(
                            'العمولة',
                            '${totalComm.toStringAsFixed(2)} د',
                            AppColors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryCard(
                            'المدفوع',
                            '${totalPaid.toStringAsFixed(2)} د',
                            Colors.green,
                          ),
                        ),
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
                    const Divider(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'العمولة (نسبة مئوية)',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _commissionPctCtrl,
                      enabled:
                          !_commissionPatchUnsupported && !_commissionPctSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        labelText: 'نسبة العمولة %',
                        hintText: 'مثال: 5 أو 10.5',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    if (_commissionPatchUnsupported)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'الميزة غير مدعومة حالياً — لا يوجد مسار PATCH للمتجر في الخادم. استخدم «إعدادات العمولة العامة» من الإعدادات.',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.tajawal(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed:
                          (_commissionPatchUnsupported || _commissionPctSaving)
                          ? null
                          : () => _saveCommissionPercent(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        minimumSize: const Size(double.infinity, 44),
                      ),
                      child: _commissionPctSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'حفظ نسبة العمولة',
                              style: GoogleFonts.tajawal(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
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
                      onPressed: () => _recordPayment(
                        context,
                        totalComm: totalComm,
                        totalPaid: totalPaid,
                        balance: balance,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'طلبات مسجلة للعمولة',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
                      ),
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
                        final shortId = oid.length > 8
                            ? oid.substring(0, 8)
                            : oid;
                        final orderTotal =
                            (o['orderTotal'] as num?)?.toDouble() ?? 0.0;
                        final comm =
                            (o['commissionAmount'] as num?)?.toDouble() ?? 0.0;
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.receipt_outlined,
                            color: AppColors.orange,
                          ),
                          title: Text(
                            'طلب #$shortId',
                            style: GoogleFonts.tajawal(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'قيمة: ${orderTotal.toStringAsFixed(2)} د',
                            style: GoogleFonts.tajawal(fontSize: 12),
                          ),
                          trailing: Text(
                            '${comm.toStringAsFixed(2)} د',
                            style: GoogleFonts.tajawal(
                              color: AppColors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'عمولات المناقصات وسجل الدفعات التفصيلي يُدار من الخادم.',
                      style: GoogleFonts.tajawal(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
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
          Text(
            value,
            style: GoogleFonts.tajawal(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
