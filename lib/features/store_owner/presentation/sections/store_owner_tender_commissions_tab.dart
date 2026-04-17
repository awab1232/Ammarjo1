import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../tenders/data/tender_repository.dart';

String _commissionFormatDate(dynamic ts) {
  if (ts == null) return '—';
  try {
    final s = (ts as dynamic).seconds;
    if (s is int) {
      return DateTime.fromMillisecondsSinceEpoch(s * 1000).toString().split('.').first;
    }
  } on Object {
    return '—';
  }
  final p = DateTime.tryParse(ts.toString());
  if (p != null) return p.toString().split('.').first;
  return '—';
}

class StoreOwnerTenderCommissionsTab extends StatefulWidget {
  const StoreOwnerTenderCommissionsTab({super.key, required this.storeId});

  final String storeId;

  @override
  State<StoreOwnerTenderCommissionsTab> createState() => _StoreOwnerTenderCommissionsTabState();
}

class _StoreOwnerTenderCommissionsTabState extends State<StoreOwnerTenderCommissionsTab> {
  static const int _pageSize = 20;
  final List<Map<String, dynamic>> _commissions = <Map<String, dynamic>>[];
  Object? _lastDoc;
  bool _isLoading = false;
  bool _hasError = false;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _hasMore = true;
      _lastDoc = null;
      _commissions.clear();
    });
    try {
      final result = await TenderRepository.instance.getStoreTenderCommissions(
        storeId: widget.storeId,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _commissions.addAll(result.items);
        _lastDoc = result.lastDocument;
        _hasMore = result.hasMore;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await TenderRepository.instance.getStoreTenderCommissions(
        storeId: widget.storeId,
        limit: _pageSize,
        startAfter: _lastDoc,
      );
      if (!mounted) return;
      setState(() {
        _commissions.addAll(result.items);
        _lastDoc = result.lastDocument;
        _hasMore = result.hasMore;
      });
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  double get _totalCommission => _commissions.fold<double>(
        0,
        (total, e) => total + ((e['commission'] as num?)?.toDouble() ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('تعذر تحميل عمولات المناقصات', style: GoogleFonts.tajawal()),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadInitial, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_isLoading && _commissions.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
    }
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: ListTile(
            leading: const Icon(Icons.percent, color: AppColors.primaryOrange),
            title: Text('إجمالي عمولات المناقصات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            subtitle: Text('${_totalCommission.toStringAsFixed(3)} د.أ', style: GoogleFonts.tajawal(color: AppColors.primaryOrange)),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadInitial,
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                  if (_hasMore && !_isLoadingMore) _loadMore();
                }
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: _commissions.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _commissions.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
                    );
                  }
                  final c = _commissions[i];
                  final ts = c['createdAt'];
                  final date = _commissionFormatDate(ts);
                  final category = c['category']?.toString() ?? '—';
                  final original = (c['originalPrice'] as num?)?.toDouble() ?? 0.0;
                  final commission = (c['commission'] as num?)?.toDouble() ?? 0.0;
                  final net = (c['netAmount'] as num?)?.toDouble() ?? 0.0;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('تاريخ: $date', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text('القسم: $category', style: GoogleFonts.tajawal(fontSize: 13)),
                          Text('المبلغ الأصلي: ${original.toStringAsFixed(3)} د.أ', style: GoogleFonts.tajawal(fontSize: 13)),
                          Text('العمولة (5%): ${commission.toStringAsFixed(3)} د.أ', style: GoogleFonts.tajawal(fontSize: 13, color: Colors.red.shade700)),
                          Text('الصافي: ${net.toStringAsFixed(3)} د.أ', style: GoogleFonts.tajawal(fontSize: 13, color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
