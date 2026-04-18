import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/seo/seo_routes.dart';
import '../../../core/seo/seo_service.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../store/presentation/store_controller.dart';
import '../data/stores_repository.dart';
import '../domain/store_model.dart';
import 'store_detail_page.dart';
import 'widgets/store_expanded_card.dart';

enum _StoreListFilter { all, rating4, offers }

/// مستوى ٢ — قائمة متاجر حسب التصنيف مع شرائح تصفية.
class StoresListPage extends StatefulWidget {
  const StoresListPage({super.key, this.category = ''});

  final String category;

  @override
  State<StoresListPage> createState() => _StoresListPageState();
}

class _StoresListPageState extends State<StoresListPage> {
  _StoreListFilter _filter = _StoreListFilter.all;
  static const int _pageSize = 10;
  final List<StoreModel> _stores = <StoreModel>[];
  String? _lastCursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  List<StoreModel> _applyFilter(List<StoreModel> list) {
    switch (_filter) {
      case _StoreListFilter.all:
        return list;
      case _StoreListFilter.rating4:
        return list.where((s) => s.rating >= 4.0).toList();
      case _StoreListFilter.offers:
        return list.where((s) => s.hasOffers).toList();
    }
  }

  /// يمنع تكرار بطاقة كتالوج عمّار جو إن وُجدت في نتائج Firestore.
  List<StoreModel> _storesExcludingCatalog() {
    return _stores
        .where((s) => s.id.toLowerCase().trim() != 'ammarjo')
        .toList();
  }

  Future<void> _loadInitial() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _stores.clear();
      _lastCursor = null;
      _hasMore = true;
    });
    try {
      final city = context.read<StoreController>().profile?.city?.trim();
      final pageState = await StoresRepository.instance.fetchApprovedStoresPage(
        city: city,
        category: widget.category,
        limit: _pageSize,
      );
      if (!mounted) return;
      switch (pageState) {
        case FeatureSuccess(:final data):
          setState(() {
            _stores.addAll(data.stores);
            _lastCursor = data.nextCursor;
            _hasMore = data.hasMore;
          });
        case FeatureMissingBackend():
        case FeatureAdminNotWired():
        case FeatureAdminMissingEndpoint():
        case FeatureCriticalPublicDataFailure():
        case FeatureFailure():
          setState(() => _loadError = 'تعذر تحميل البيانات');
      }
    } on Object {
      if (!mounted) return;
      debugPrint('StoresList load error');
      setState(() => _loadError = 'تعذر تحميل البيانات');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final city = context.read<StoreController>().profile?.city?.trim();
      final pageState = await StoresRepository.instance.fetchApprovedStoresPage(
        city: city,
        category: widget.category,
        limit: _pageSize,
        startAfter: _lastCursor,
      );
      if (!mounted) return;
      switch (pageState) {
        case FeatureSuccess(:final data):
          setState(() {
            _stores.addAll(data.stores);
            _lastCursor = data.nextCursor;
            _hasMore = data.hasMore;
          });
        case FeatureMissingBackend():
        case FeatureAdminNotWired():
        case FeatureAdminMissingEndpoint():
        case FeatureCriticalPublicDataFailure():
        case FeatureFailure():
          break;
      }
    } on Object {
      debugPrint('StoresList loadMore error');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// تمرير واحد: شرائح التصفية + عمّار جو أولاً (نفس [StoreExpandedCard]) + المتاجر الأخرى.
  Widget _buildBody(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_loadError!, style: GoogleFonts.tajawal()),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadInitial,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    final filtered = _applyFilter(_storesExcludingCatalog());

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _chip('الكل', _StoreListFilter.all),
              const SizedBox(width: 8),
              _chip('تقييم 4+', _StoreListFilter.rating4),
              const SizedBox(width: 8),
              _chip('عروض', _StoreListFilter.offers),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: StoreExpandedCard(
          store: ammarJoCatalogStoreModel(),
          onVisitStore: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => StoreDetailPage(store: ammarJoCatalogStoreModel()),
              ),
            );
          },
        ),
      ),
      if (_loading && _stores.isEmpty)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, _) => _buildShimmerCard(),
            childCount: 4,
          ),
        )
      else if (filtered.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyStateWidget(
            type: EmptyStateType.stores,
            onAction: _loadInitial,
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            if (i >= filtered.length) {
              if (!_loadingMore) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.orange),
                ),
              );
            }
            final s = filtered[i];
            return StoreExpandedCard(
              store: s,
              onVisitStore: () {
                _showStoreInfoSheet(s);
              },
            );
          }, childCount: filtered.length + (_loadingMore ? 1 : 0)),
        ),
    ];

    return RefreshIndicator(
      color: AppColors.primaryOrange,
      onRefresh: _loadInitial,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical &&
              n.metrics.pixels >= n.metrics.maxScrollExtent - 320) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: slivers,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ = context.watch<StoreController>();
    SeoService.apply(
      SeoData(
        title: '${widget.category} | AmmarJo',
        description: 'Browse ${widget.category} stores on AmmarJo.',
        keywords: 'AmmarJo, stores, ${widget.category}',
        path: SeoRoutes.category(widget.category),
        structuredData: <Map<String, dynamic>>[
          <String, dynamic>{
            '@context': 'https://schema.org',
            '@type': 'CollectionPage',
            'name': widget.category,
            'description': 'Browse ${widget.category} stores on AmmarJo.',
          },
        ],
      ),
      updatePath: true,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(
          widget.category,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _chip(String label, _StoreListFilter value) {
    final sel = _filter == value;
    return FilterChip(
      label: Text(
        label,
        style: GoogleFonts.tajawal(
          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      selected: sel,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.lightOrange,
      checkmarkColor: AppColors.darkOrange,
      labelStyle: GoogleFonts.tajawal(
        color: sel ? AppColors.darkOrange : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Future<void> _showStoreInfoSheet(StoreModel store) async {
    await AppBottomSheet.show<void>(
      context: context,
      title: 'معلومات المتجر',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.surfaceSecondary,
            child: Text(
              store.name.isNotEmpty ? store.name[0] : 'م',
              style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          Text(store.name, textAlign: TextAlign.center, style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('التصنيف: ${store.category}', textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('التقييم: ${store.rating.toStringAsFixed(1)}', textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => StoreDetailPage(store: store)),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            child: Text('دخول المتجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

