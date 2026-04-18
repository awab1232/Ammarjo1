import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/widgets/home_page_shimmers.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesale_order_model.dart';

class WholesaleOrdersSection extends StatefulWidget {
  const WholesaleOrdersSection({super.key, required this.wholesalerId});

  final String wholesalerId;

  @override
  State<WholesaleOrdersSection> createState() => _WholesaleOrdersSectionState();
}

class _WholesaleOrdersSectionState extends State<WholesaleOrdersSection> {
  static const int _pageSize = 20;
  final List<WholesaleOrderModel> _orders = <WholesaleOrderModel>[];
  String? _nextCursor;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;

  static const List<String> _statusChoices = <String>[
    'pending',
    'confirmed',
    'processing',
    'shipped',
    'delivered',
    'cancelled',
  ];

  List<String> _allowedForwardStatuses(String current) {
    final idx = _statusChoices.indexOf(current);
    if (idx < 0) return _statusChoices;
    if (current == 'delivered' || current == 'cancelled') return <String>[current];
    return _statusChoices.sublist(idx);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  Future<void> _loadInitial() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _orders.clear();
      _nextCursor = null;
      _hasMore = true;
    });
    try {
      final result = await WholesaleRepository.instance.getWholesaleOrdersPage(
        limit: _pageSize,
        wholesalerId: widget.wholesalerId,
      );
      if (!mounted) return;
      setState(() {
        _orders.addAll(result.items);
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
      });
    } on Object {
      debugPrint('WholesaleOrdersSection: load orders failed.');
      if (!mounted) return;
      setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await WholesaleRepository.instance.getWholesaleOrdersPage(
        limit: _pageSize,
        wholesalerId: widget.wholesalerId,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _orders.addAll(result.items);
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
      });
    } on Object {
      debugPrint('WholesaleOrdersSection: load more failed.');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('حدث خطأ في تحميل طلبات الجملة'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadInitial, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_isLoading && _orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.all(12),
        children: const [
          HomeStoreListSkeleton(rows: 5),
        ],
      );
    }
    if (_orders.isEmpty) {
      return Center(child: Text('لا توجد طلبات واردة', style: GoogleFonts.tajawal()));
    }
    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
            if (_hasMore && !_isLoadingMore) {
              _loadMore();
            }
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _orders.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == _orders.length) {
              return _isLoadingMore
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: HomeStoreListSkeleton(rows: 1),
                    )
                  : const SizedBox.shrink();
            }
            final o = _orders[i];
            final statusVal = _statusChoices.contains(o.status) ? o.status : _statusChoices.first;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(o.storeName, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                    Text('${o.subtotal.toStringAsFixed(2)} د.أ', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: statusVal,
                      decoration: InputDecoration(labelText: 'تحديث الحالة', labelStyle: GoogleFonts.tajawal()),
                      items: _allowedForwardStatuses(statusVal)
                          .map((s) => DropdownMenuItem<String>(value: s, child: Text(s, style: GoogleFonts.tajawal())))
                          .toList(),
                      onChanged: (statusVal == 'delivered' || statusVal == 'cancelled')
                          ? null
                          : (nv) async {
                        if (nv == null) return;
                        if (nv == statusVal) return;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await WholesaleRepository.instance.updateWholesaleOrderStatus(orderId: o.orderId, status: nv);
                          if (context.mounted) {
                            messenger.showSnackBar(SnackBar(content: Text('تم تحديث حالة الطلب', style: GoogleFonts.tajawal())));
                          }
                        } on Object {
                          debugPrint('[WholesaleOrdersSection] updateWholesaleOrderStatus failed.');
                          if (context.mounted) {
                            messenger.showSnackBar(SnackBar(content: Text('تعذّر تحديث حالة الطلب.', style: GoogleFonts.tajawal())));
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

