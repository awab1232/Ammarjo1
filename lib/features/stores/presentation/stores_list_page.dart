import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/data/repositories/home_repository.dart';
import '../../../core/models/home_section.dart';
import '../../../core/models/sub_category.dart';
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

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, GlobalKey> _groupHeaderKeys = <String, GlobalKey>{};

  /// أقسام فرعية من الـ API مع متاجر كل قسم (`GET /stores/by-subcategory/:id`).
  List<({SubCategory sub, List<StoreModel> stores})>? _subcategoryGroups;
  bool _groupingBusy = false;
  String? _groupingError;

  bool get _useGroupedLayout =>
      _subcategoryGroups != null && _subcategoryGroups!.isNotEmpty && widget.category.trim().isNotEmpty;

  void _onSearchChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadInitial();
      if (!mounted) return;
      await _tryAttachSubcategoryGrouping();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static bool _namesMatch(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }

  Future<void> _tryAttachSubcategoryGrouping({bool forceRefresh = false}) async {
    if (widget.category.trim().isEmpty) return;
    setState(() {
      _groupingBusy = true;
      _groupingError = null;
    });
    try {
      final sectionsState = await HomeRepository.instance.getSections(forceRefresh: forceRefresh);
      if (!mounted) return;
      if (sectionsState is! FeatureSuccess<List<HomeSection>>) {
        setState(() {
          _groupingBusy = false;
          _subcategoryGroups = null;
        });
        return;
      }
      HomeSection? matched;
      for (final s in sectionsState.data) {
        if (_namesMatch(s.name, widget.category)) {
          matched = s;
          break;
        }
      }
      if (matched == null) {
        setState(() {
          _groupingBusy = false;
          _subcategoryGroups = null;
        });
        return;
      }
      final subsState = await HomeRepository.instance.getSubCategories(matched.id, forceRefresh: forceRefresh);
      if (!mounted) return;
      if (subsState is! FeatureSuccess<List<SubCategory>> || subsState.data.isEmpty) {
        setState(() {
          _groupingBusy = false;
          _subcategoryGroups = null;
        });
        return;
      }
      final subs = subsState.data;
      final pairs = await Future.wait(
        subs.map((sub) async {
          final r = await StoresRepository.instance.getStoresBySubCategory(sub.id);
          final raw = switch (r) {
            FeatureSuccess<List<StoreModel>>(:final data) => data,
            _ => const <StoreModel>[],
          };
          return (sub: sub, stores: raw);
        }),
      );
      if (!mounted) return;
      _groupHeaderKeys.clear();
      for (final p in pairs) {
        _groupHeaderKeys.putIfAbsent(p.sub.id, () => GlobalKey());
      }
      setState(() {
        _subcategoryGroups = pairs;
        _groupingBusy = false;
      });
    } on Object catch (e) {
      debugPrint('StoresList subcategory grouping: $e');
      if (!mounted) return;
      setState(() {
        _groupingBusy = false;
        _groupingError = 'تعذر تحميل التصنيفات الفرعية';
        _subcategoryGroups = null;
      });
    }
  }

  void _scrollToSubcategory(String subId) {
    final key = _groupHeaderKeys[subId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
  }

  List<({SubCategory sub, List<StoreModel> stores})> _visibleGrouped() {
    final base = _subcategoryGroups;
    if (base == null) return List<({SubCategory sub, List<StoreModel> stores})>.empty();
    final q = _searchController.text.trim().toLowerCase();
    return [
      for (final g in base)
        (
          sub: g.sub,
          stores: _applyFilter(g.stores)
              .where(
                (s) =>
                    q.isEmpty ||
                    s.name.toLowerCase().contains(q) ||
                    s.description.toLowerCase().contains(q),
              )
              .toList(),
        ),
    ];
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchController,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: 'ابحث في المتاجر…',
          hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryOrange),
          suffixIcon: _searchController.text.trim().isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildSubcategoryChipsStrip() {
    final groups = _subcategoryGroups;
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: groups.length + 1,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              return ActionChip(
                label: Text('الكل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                onPressed: () {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
              );
            }
            final sub = groups[i - 1].sub;
            return ActionChip(
              label: Text(sub.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
              onPressed: () => _scrollToSubcategory(sub.id),
            );
          },
        ),
      ),
    );
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

  /// شريط بحث + تصفية + (اختياري) تجميع حسب تصنيفات فرعية من الـ API عند تطابق اسم القسم مع [widget.category].
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

    final filtered = _applyFilter(_stores);
    final q = _searchController.text.trim().toLowerCase();
    final flatForSearch = q.isEmpty
        ? filtered
        : filtered
            .where(
              (s) => s.name.toLowerCase().contains(q) || s.description.toLowerCase().contains(q),
            )
            .toList();

    final slivers = <Widget>[
      if (widget.category.trim().isNotEmpty) SliverToBoxAdapter(child: _buildSearchBar()),
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
      if (_groupingBusy && !_useGroupedLayout)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: LinearProgressIndicator(minHeight: 3, color: AppColors.primaryOrange),
          ),
        ),
      if (_groupingError != null && !_useGroupedLayout)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(_groupingError!, style: GoogleFonts.tajawal(color: AppColors.textSecondary))),
                TextButton(
                  onPressed: () => _tryAttachSubcategoryGrouping(forceRefresh: true),
                  child: Text('إعادة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      if (_useGroupedLayout) SliverToBoxAdapter(child: _buildSubcategoryChipsStrip()),
    ];

    if (_useGroupedLayout) {
      final visible = _visibleGrouped();
      final anyStores = visible.any((g) => g.stores.isNotEmpty);
      if (!anyStores) {
        slivers.add(
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              type: EmptyStateType.search,
              customTitle: q.isEmpty ? 'لا متاجر في التصنيفات الفرعية' : 'لا نتائج للبحث',
              actionLabel: 'تحديث',
              onAction: () async {
                _searchController.clear();
                await _tryAttachSubcategoryGrouping(forceRefresh: true);
              },
            ),
          ),
        );
      } else {
        for (final g in visible) {
          slivers.add(
            SliverToBoxAdapter(
              key: _groupHeaderKeys[g.sub.id],
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        g.sub.name,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          if (g.stores.isEmpty) {
            slivers.add(
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'لا متاجر في هذا التصنيف الفرعي.',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ),
            );
          } else {
            slivers.add(
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final s = g.stores[i];
                    return StoreExpandedCard(
                      store: s,
                      onVisitStore: () => _showStoreInfoSheet(s),
                    );
                  },
                  childCount: g.stores.length,
                ),
              ),
            );
          }
        }
      }
    } else {
      if (_loading && _stores.isEmpty) {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, _) => _buildShimmerCard(),
              childCount: 4,
            ),
          ),
        );
      } else if (flatForSearch.isEmpty) {
        slivers.add(
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              type: EmptyStateType.stores,
              customTitle: q.isEmpty ? null : 'لا نتائج للبحث',
              onAction: _loadInitial,
            ),
          ),
        );
      } else {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate((context, i) {
              if (i >= flatForSearch.length) {
                if (!_loadingMore) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  child: _buildShimmerCard(),
                );
              }
              final s = flatForSearch[i];
              return StoreExpandedCard(
                store: s,
                onVisitStore: () {
                  _showStoreInfoSheet(s);
                },
              );
            }, childCount: flatForSearch.length + (_loadingMore ? 1 : 0)),
          ),
        );
      }
    }

    return RefreshIndicator(
      color: AppColors.primaryOrange,
      onRefresh: () async {
        await _loadInitial();
        if (!mounted) return;
        await _tryAttachSubcategoryGrouping(forceRefresh: true);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (!_useGroupedLayout &&
              n.metrics.axis == Axis.vertical &&
              n.metrics.pixels >= n.metrics.maxScrollExtent - 320) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
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

