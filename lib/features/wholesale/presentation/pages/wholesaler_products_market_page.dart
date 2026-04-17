import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesale_product_model.dart';
import '../../domain/wholesaler_model.dart';
import 'wholesaler_product_detail_page.dart';

class WholesalerProductsMarketPage extends StatefulWidget {
  const WholesalerProductsMarketPage({super.key, required this.wholesaler});

  final WholesalerModel wholesaler;

  @override
  State<WholesalerProductsMarketPage> createState() => _WholesalerProductsMarketPageState();
}

class _WholesalerProductsMarketPageState extends State<WholesalerProductsMarketPage> {
  static const int _pageSize = 20;
  final List<WholesaleProduct> _products = [];
  String? _nextCursor;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _filterCategoryId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _products.clear();
      _nextCursor = null;
      _hasMore = true;
    });
    try {
      final pageState = await WholesaleRepository.instance.fetchWholesalerProductsPage(
        widget.wholesaler.id,
        limit: _pageSize,
      );
      if (pageState is! FeatureSuccess<({List<WholesaleProduct> products, String? nextCursor})>) {
        throw StateError(
          pageState is FeatureFailure<({List<WholesaleProduct> products, String? nextCursor})>
              ? pageState.message
              : 'FAILED_TO_LOAD_WHOLESALE_PRODUCTS',
        );
      }
      final page = pageState.data;
      if (!mounted) return;
      setState(() {
        _products.addAll(page.products);
        _nextCursor = page.nextCursor;
        _hasMore = _nextCursor != null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final pageState = await WholesaleRepository.instance.fetchWholesalerProductsPage(
        widget.wholesaler.id,
        limit: _pageSize,
        cursor: _nextCursor,
      );
      if (pageState is! FeatureSuccess<({List<WholesaleProduct> products, String? nextCursor})>) {
        throw StateError(
          pageState is FeatureFailure<({List<WholesaleProduct> products, String? nextCursor})>
              ? pageState.message
              : 'FAILED_TO_LOAD_WHOLESALE_PRODUCTS',
        );
      }
      final page = pageState.data;
      if (!mounted) return;
      setState(() {
        _products.addAll(page.products);
        _nextCursor = page.nextCursor;
        _hasMore = _nextCursor != null;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  double _minPrice(WholesaleProduct p) {
    if (p.quantityPrices.isEmpty) return 0;
    return p.quantityPrices.map((e) => e.price).reduce((a, b) => a < b ? a : b);
  }

  List<WholesaleProduct> get _visible {
    if (_filterCategoryId == null) return _products;
    return _products.where((p) => p.categoryId == _filterCategoryId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>{for (final p in _products) if ((p.categoryId ?? '').trim().isNotEmpty) p.categoryId!.trim()}.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.wholesaler.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (categories.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: FilterChip(
                        label: Text('الكل', style: GoogleFonts.tajawal()),
                        selected: _filterCategoryId == null,
                        onSelected: (_) => setState(() => _filterCategoryId = null),
                        selectedColor: AppColors.primaryOrange.withValues(alpha: 0.25),
                      ),
                    ),
                    ...categories.map((c) {
                      final sel = _filterCategoryId == c;
                      return Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: FilterChip(
                          label: Text(c, style: GoogleFonts.tajawal()),
                          selected: sel,
                          onSelected: (_) => setState(() => _filterCategoryId = c),
                          selectedColor: AppColors.primaryOrange.withValues(alpha: 0.25),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
                  : Builder(
                      builder: (context) {
                        final visible = _visible;
                        if (visible.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _filterCategoryId != null ? 'لا منتجات في هذا القسم.' : 'لا توجد منتجات بعد.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: visible.length + 1,
                          itemBuilder: (context, i) {
                            if (i >= visible.length) {
                              if (!_hasMore) return const SizedBox(height: 12);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: FilledButton(
                                    onPressed: _loadingMore ? null : _loadMore,
                                    child: Text(_loadingMore ? 'جارٍ التحميل...' : 'تحميل المزيد', style: GoogleFonts.tajawal()),
                                  ),
                                ),
                              );
                            }
                            final p = visible[i];
                            final min = _minPrice(p);
                            return Card(
                              child: ListTile(
                                leading: p.imageUrl.trim().isNotEmpty
                                    ? CircleAvatar(backgroundImage: NetworkImage(p.imageUrl))
                                    : const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                                title: Text(p.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                subtitle: Text(
                                  'الوحدة: ${p.unit}\nيبدأ من: ${min.toStringAsFixed(2)} د.أ',
                                  style: GoogleFonts.tajawal(fontSize: 12),
                                  textAlign: TextAlign.right,
                                ),
                                trailing: FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                                  onPressed: () {
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => WholesalerProductDetailPage(
                                          wholesalerId: widget.wholesaler.id,
                                          wholesalerName: widget.wholesaler.name,
                                          wholesalerOwnerId: widget.wholesaler.ownerId,
                                          wholesalerEmail: widget.wholesaler.email,
                                          product: p,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text('عرض التفاصيل', style: GoogleFonts.tajawal(color: Colors.white)),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
