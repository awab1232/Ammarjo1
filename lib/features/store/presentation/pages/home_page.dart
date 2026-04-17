// ignore_for_file: unused_import, unused_field, unused_element, unnecessary_underscores, prefer_final_fields

import 'dart:async';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/home_category_sections.dart';
import '../../../../core/config/main_category_hierarchy.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/home_repository.dart';
import '../../../../core/data/repositories/store_repository.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/ammarjo_page_banner_fallback.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/feature_state_builder.dart';
import '../../../../core/services/growth_push_logic_service.dart';
import '../../domain/models.dart';
import '../../domain/wp_home_banner.dart';
import '../../../promotions/data/promotion_repository.dart';
import '../../../promotions/domain/promotion_model.dart';
import '../../../promotions/presentation/pages/promotions_page.dart';
import '../../../stores/domain/store_model.dart';
import '../controllers/catalog_controller.dart';
import '../controllers/filter_controller.dart';
import '../controllers/search_controller.dart';
import '../store_controller.dart';
import '../widgets/catalog_filter_bottom_sheet.dart';
import '../widgets/compact_product_card.dart';
import 'main_category_detail_page.dart';
import 'products_horizontal_section_page.dart';
import 'store_search_page.dart';
import 'sub_category_screen.dart';

List<Product> _homeDisplayedProducts(SearchController search, FilterController filter, CatalogController catalog) {
  if (filter.isFilterMode) return filter.filteredProducts;
  if (search.isSearchMode) return search.searchResults;
  return catalog.products;
}

/// بانر الويب: نسبة العرض إلى الارتفاع (مثال 16:9). غيّرها إلى `21 / 9` للبانر العريض.
const double _kHomeBannerAspectRatio = 16 / 9;

const double _kHomeBannerRadius = 12.0;

class HomePage extends StatefulWidget {
  final VoidCallback? onOpenCart;
  final VoidCallback? onOpenMarketplace;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onOpenMaintenance;
  const HomePage({
    super.key,
    this.onOpenCart,
    this.onOpenMarketplace,
    this.onOpenDrawer,
    this.onOpenMaintenance,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final PageController _bannerController = PageController();
  final PageController _dealsController = PageController();
  final GlobalKey<State<StatefulWidget>> _homeSearchBarKey = GlobalKey<State<StatefulWidget>>();
  int _bannerIndex = 0;
  int _dealsIndex = 0;
  bool _refreshingHome = false;
  late Future<FeatureState<List<HomeSection>>> _homeSectionsFuture;
  late Future<FeatureState<List<StoreModel>>> _featuredStoresFuture;
  late Future<FeatureState<List<StoreModel>>> _topStoresFuture;

  @override
  void initState() {
    super.initState();
    _homeSectionsFuture = HomeRepository.instance.getSections();
    final storeRepo = RestStoreRepository.instance;
    _featuredStoresFuture = storeRepo.fetchApprovedStores();
    _topStoresFuture = storeRepo.fetchApprovedStores();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  Future<void> _loadInitialData() async {
    GrowthPushLogicService.instance.triggerAbandonedCartIfNeeded();
    final store = context.read<StoreController>();
    final catalog = context.read<CatalogController>();
    if (catalog.products.isNotEmpty && catalog.categories.isNotEmpty) return;
    final stopwatch = Stopwatch()..start();
    await Future.wait<void>([
      catalog.loadInitialProducts(),
      store.loadWpHomeBanners(),
      store.loadCategories(),
    ]);
    await Future.wait<void>([
      store.loadHomeSections(),
      store.loadBannerProducts(),
    ]);
    stopwatch.stop();
    debugPrint('⏱️ Home initial load took: ${stopwatch.elapsedMilliseconds}ms');
  }

  Future<void> _refreshHomeData(StoreController store) async {
    if (_refreshingHome) return;
    _refreshingHome = true;
    final stopwatch = Stopwatch()..start();
    try {
      await Future.wait<void>([
        store.loadProducts(),
        store.loadWpHomeBanners(),
        store.loadCategories(),
      ]);
      await Future.wait<void>([
        store.loadHomeSections(),
        store.loadBannerProducts(),
      ]);
      _homeSectionsFuture = HomeRepository.instance.getSections();
      final storeRepo = RestStoreRepository.instance;
      _featuredStoresFuture = storeRepo.fetchApprovedStores();
      _topStoresFuture = storeRepo.fetchApprovedStores();
      stopwatch.stop();
      debugPrint('⏱️ Home refresh took: ${stopwatch.elapsedMilliseconds}ms');
    } finally {
      _refreshingHome = false;
    }
  }

  void _handleSectionTap(HomeSection section) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SubCategoryScreen(section: section),
      ),
    );
  }

  Widget _buildHomeSectionsGrid() {
    return FutureBuilder<FeatureState<List<HomeSection>>>(
      future: _homeSectionsFuture,
      initialData: const FeatureFailure<List<HomeSection>>('LOADING_HOME_SECTIONS'),
      builder: (context, snapshot) {
        final state = snapshot.requireData;
        return buildFeatureStateUi<List<HomeSection>>(
          context: context,
          state: state,
          dataBuilder: (context, sections) {
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: sections.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.22,
              ),
              itemBuilder: (context, index) {
                final section = sections[index];
                final imageRaw = section.image;
                final imageUrl = imageRaw == null ? '' : webSafeImageUrl(imageRaw);
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _handleSectionTap(section),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (imageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AmmarCachedImage(imageUrl: imageUrl, width: 52, height: 52, fit: BoxFit.cover),
                          )
                        else
                          const Icon(Icons.grid_view_rounded, color: AppColors.accent, size: 42),
                        const SizedBox(height: 8),
                        Text(
                          section.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.heading),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _bannerController.dispose();
    _dealsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchMode = context.select<SearchController, bool>((s) => s.isSearchMode);
    final filterMode = context.select<FilterController, bool>((f) => f.isFilterMode);
    final store = context.read<StoreController>();

        return Scaffold(
      backgroundColor: AppColors.background,
          appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        leading: Navigator.of(context).canPop() ? const AppBarBackButton() : null,
        title: Text('متجر عمار جو', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: SafeArea(
        child: (searchMode || filterMode) ? _buildSearchFilterScroll(context, store) : _buildCatalogScroll(context, store),
      ),
    );
  }

  Widget _buildCatalogScroll(BuildContext context, StoreController store) {
    final catalog = context.watch<CatalogController>();
    final sessionLoading = context.select<StoreController, bool>((s) => s.isLoading);

    if ((sessionLoading || catalog.isLoading) && catalog.products.isEmpty) {
      return const _HomeLoadingShimmer();
    }
    if (catalog.errorMessage != null && catalog.products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(catalog.errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: () => _refreshHomeData(store),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: false,
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: widget.onOpenDrawer != null
                ? IconButton(
                    icon: const Icon(Icons.menu_rounded, color: AppColors.appBarBackIcon),
                    onPressed: widget.onOpenDrawer,
                  )
                : null,
            title: Text(
              'عمّارجو',
              style: GoogleFonts.tajawal(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: AppColors.heading,
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary),
                onPressed: () {
                  // شاشة الإشعارات مستقبلاً.
                },
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _HomeSearchBar(
                  key: _homeSearchBarKey,
                  onOpenFullSearch: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const StoreSearchPage()),
                    );
                  },
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _HomeBannersCarousel(store: store),
          ),
          SliverToBoxAdapter(
            child: _QuickCategoriesRow(onOpenMaintenance: widget.onOpenMaintenance),
          ),
          const SliverToBoxAdapter(
            child: _SecondaryBannerStrip(),
          ),
          SliverToBoxAdapter(
            child: _FeaturedOffersSection(future: _featuredStoresFuture),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: _TopStoresSection(future: _topStoresFuture),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildSearchFilterScroll(BuildContext context, StoreController store) {
    final search = context.watch<SearchController>();
    final filter = context.watch<FilterController>();
    final catalog = context.read<CatalogController>();
    final displayed = _homeDisplayedProducts(search, filter, catalog);

    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: () async {
        if (search.isSearchMode) {
          await store.performSearch(search.searchQuery);
        } else if (filter.isFilterMode && filter.activeFilters != null) {
          await store.applyFilters(filter.activeFilters!);
        } else {
          await _refreshHomeData(store);
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.axis != Axis.vertical) return false;
          if (search.isSearchMode) {
            if (search.searchHasMore &&
                !search.isLoadingMoreSearch &&
                !search.isSearching &&
                n.metrics.pixels >= n.metrics.maxScrollExtent - 320) {
              store.loadMoreSearchResults();
            }
            return false;
          }
          if (filter.isFilterMode) {
            if (filter.filterHasMore &&
                !filter.isLoadingMoreFilter &&
                !filter.isApplyingFilters &&
                n.metrics.pixels >= n.metrics.maxScrollExtent - 320) {
              store.loadMoreFilterResults();
            }
            return false;
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _HomeSearchBar(
                  key: _homeSearchBarKey,
                  onOpenFullSearch: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const StoreSearchPage()),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Text(
                      filter.isFilterMode ? 'نتائج التصفية' : 'نتائج البحث',
                      style: GoogleFonts.tajawal(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.heading,
                      ),
                    ),
                    const Spacer(),
                    if (search.isSearchMode)
                      TextButton(
                        onPressed: () {
                          (_homeSearchBarKey.currentState as _HomeSearchBarState?)?.clearField();
                          store.clearSearch();
                        },
                        child: Text('مسح البحث', style: GoogleFonts.tajawal(color: AppColors.accent)),
                      ),
                    if (filter.isFilterMode)
                      TextButton(
                        onPressed: () => store.clearFilters(),
                        child: Text('إلغاء التصفية', style: GoogleFonts.tajawal(color: AppColors.accent)),
                      ),
                  ],
                ),
              ),
            ),
            if ((search.isSearching || filter.isApplyingFilters) && displayed.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: _SearchResultsGridShimmer(),
                ),
              )
            else if (displayed.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: EmptyStateWidget(
                    type: EmptyStateType.search,
                    onAction: () => _refreshHomeData(store),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final p = displayed[i];
                      return CompactProductCard(store: store, product: p);
                    },
                    childCount: displayed.length,
                  ),
                ),
              ),
            if ((search.isSearchMode && search.isLoadingMoreSearch) || (filter.isFilterMode && filter.isLoadingMoreFilter))
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

/// تحميل أولي للرئيسية — بدل مؤشر دوّار فقط (UX أوضح أثناء جلب الكتالوج).
class _HomeLoadingShimmer extends StatelessWidget {
  const _HomeLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: w * 9 / 16,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(height: 16),
          ...List.generate(
            5,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 72,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBannersCarousel extends StatelessWidget {
  final StoreController store;
  const _HomeBannersCarousel({required this.store});

  @override
  Widget build(BuildContext context) {
    final slides = store.wpHomeBanners;
    final hasSlides = slides.isNotEmpty;
    final items = hasSlides
        ? slides
            .take(5)
            .map(
              (s) => _BannerCard(
                imageUrl: webSafeImageUrl(s.imageUrl),
                title: s.title,
                linkUrl: s.linkUrl,
              ),
            )
            .toList()
        : List.generate(
            3,
            (i) => const _SecondaryBannerStrip(),
          );

    final width = MediaQuery.sizeOf(context).width;
    final height = width * 9 / 16;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: CarouselSlider(
        options: CarouselOptions(
          height: height,
          viewportFraction: 0.9,
          autoPlay: hasSlides && items.length > 1,
          autoPlayInterval: const Duration(seconds: 4),
          enlargeCenterPage: true,
        ),
        items: items,
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final String imageUrl;
  final String? title;
  final String? linkUrl;

  const _BannerCard({
    required this.imageUrl,
    this.title,
    this.linkUrl,
  });

  Future<void> _openLink() async {
    if (linkUrl == null || linkUrl!.isEmpty) return;
    final uri = Uri.tryParse(linkUrl!);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              AmmarCachedImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
              )
            else
              const _SecondaryBannerStrip(),
            if (title != null && title!.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  child: Text(
                    title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (linkUrl == null || linkUrl!.isEmpty) return card;
    return GestureDetector(onTap: _openLink, child: card);
  }
}

class _QuickCategoriesRow extends StatelessWidget {
  final VoidCallback? onOpenMaintenance;

  const _QuickCategoriesRow({this.onOpenMaintenance});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'خدمات رئيسية',
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _QuickCategoryCard(
                  icon: Icons.home_repair_service_rounded,
                  label: 'مواد بناء',
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickCategoryCard(
                  icon: Icons.handyman_rounded,
                  label: 'أدوات',
                  color: AppColors.accentOrange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickCategoryCard(
                  icon: Icons.engineering_rounded,
                  label: 'فنيين',
                  color: AppColors.darkOrange,
                  onTap: onOpenMaintenance,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickCategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickCategoryCard({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Icon(icon, color: color, size: 26),
              ),
              const Spacer(),
              Text(
                label,
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'استكشف العروض',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryBannerStrip extends StatelessWidget {
  const _SecondaryBannerStrip();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              AppColors.primaryOrange,
              AppColors.orangeMedium,
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'توصيل سريع من متاجر معتمدة في عمّان وباقي المحافظات.',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedOffersSection extends StatelessWidget {
  final Future<FeatureState<List<StoreModel>>> future;

  const _FeaturedOffersSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'عروض المتاجر',
                style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.heading,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const PromotionsPage()),
                  );
                },
                child: Text('عرض الكل', style: GoogleFonts.tajawal(color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 160,
            child: FutureBuilder<FeatureState<List<StoreModel>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const EmptyStateWidget(type: EmptyStateType.generic);
                }
                if (!snapshot.hasData) {
                  return _StoresStripShimmer();
                }
                final state = snapshot.requireData;
                return buildFeatureStateUi<List<StoreModel>>(
                  context: context,
                  state: state,
                  dataBuilder: (context, stores) {
                    final offers = stores.where((s) => s.hasOffers).toList()
                      ..sort((a, b) {
                        final af = a.isFeatured ? 1 : 0;
                        final bf = b.isFeatured ? 1 : 0;
                        if (af != bf) return bf.compareTo(af);
                        return b.rating.compareTo(a.rating);
                      });
                    GrowthPushLogicService.instance.triggerNewOffersSignal(
                      offersCount: offers.length,
                    );
                    if (offers.isEmpty) {
                      return const EmptyStateWidget(type: EmptyStateType.products);
                    }
                    final visible = offers.length > 10 ? offers.sublist(0, 10) : offers;
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final s = visible[index];
                        return _StoreOfferCard(store: s);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopStoresSection extends StatelessWidget {
  final Future<FeatureState<List<StoreModel>>> future;

  const _TopStoresSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'أفضل المتاجر',
            style: GoogleFonts.tajawal(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.heading,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: FutureBuilder<FeatureState<List<StoreModel>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const EmptyStateWidget(type: EmptyStateType.generic);
                }
                if (!snapshot.hasData) {
                  return _StoresStripShimmer(circleOnly: true);
                }
                final state = snapshot.requireData;
                return buildFeatureStateUi<List<StoreModel>>(
                  context: context,
                  state: state,
                  dataBuilder: (context, stores) {
                    final sorted = [...stores]..sort((a, b) {
                      final af = a.isFeatured ? 1 : 0;
                      final bf = b.isFeatured ? 1 : 0;
                      if (af != bf) return bf.compareTo(af);
                      return b.rating.compareTo(a.rating);
                    });
                    if (sorted.isEmpty) return const EmptyStateWidget(type: EmptyStateType.products);
                    final visible = sorted.length > 12 ? sorted.sublist(0, 12) : sorted;
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final s = visible[index];
                        return _TopStoreAvatar(store: s);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreOfferCard extends StatelessWidget {
  final StoreModel store;

  const _StoreOfferCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Material(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // يمكن الربط لاحقاً بصفحة تفاصيل المتجر.
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.orangeLight,
                  backgroundImage: store.logo.isNotEmpty ? NetworkImage(webSafeImageUrl(store.logo)) : null,
                  child: store.logo.isEmpty
                      ? const Icon(Icons.store_rounded, color: AppColors.orange)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.star_rounded, color: AppColors.orange, size: 16),
                          const SizedBox(width: 2),
                          Text(
                            store.rating.toStringAsFixed(1),
                            style: GoogleFonts.tajawal(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${store.reviewCount} تقييم',
                            style: GoogleFonts.tajawal(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (store.isFeatured)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber),
                          ),
                          child: Text(
                            '⭐ متجر مميز',
                            style: GoogleFonts.tajawal(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          store.isFeatured ? '🔥 عرض اليوم' : '⏳ ينتهي قريبًا',
                          style: GoogleFonts.tajawal(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopStoreAvatar extends StatelessWidget {
  final StoreModel store;

  const _TopStoreAvatar({required this.store});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.orangeLight,
          backgroundImage: store.logo.isNotEmpty ? NetworkImage(webSafeImageUrl(store.logo)) : null,
          child: store.logo.isEmpty
              ? const Icon(Icons.storefront_rounded, color: AppColors.orange)
              : null,
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 70,
          child: Text(
            store.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 10,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _StoresStripShimmer extends StatelessWidget {
  final bool circleOnly;

  const _StoresStripShimmer({this.circleOnly = false});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemBuilder: (_, __) => circleOnly
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(radius: 26, backgroundColor: Colors.white),
                  const SizedBox(height: 6),
                  Container(
                    width: 60,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              )
            : Container(
                width: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: 4,
      ),
    );
  }
}

/// شريط بحث خادمي + تصفية؛ رابط لصفحة [StoreSearchPage] للبحث المتقدّم.
class _HomeSearchBar extends StatefulWidget {
  // مفتاح [GlobalKey] يمنع const.
  // ignore: prefer_const_constructors_in_immutables
  _HomeSearchBar({super.key, required this.onOpenFullSearch});

  final VoidCallback onOpenFullSearch;

  @override
  State<_HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<_HomeSearchBar> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  bool _searchingByButton = false;

  void clearField() => _ctrl.clear();

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filterMode = context.select<FilterController, bool>((f) => f.isFilterMode);
    final store = context.read<StoreController>();
    final search = context.read<SearchController>();

    return Material(
      elevation: 0,
      color: AppColors.background,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'تصفية',
              onPressed: () => showCatalogFilterBottomSheet(context, store),
              icon: Icon(
                Icons.tune_rounded,
                color: filterMode ? AppColors.orange : AppColors.textSecondary,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () async {
                    final t = v.trim();
                    if (t.length < 2) {
                      search.clearSearch();
                      return;
                    }
                    await search.performSearch(t);
                  });
                },
                textInputAction: TextInputAction.search,
                style: GoogleFonts.tajawal(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'ابحث في المنتجات…',
                  hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search_rounded, color: AppColors.accent),
              onPressed: _searchingByButton
                  ? null
                  : () async {
                      setState(() => _searchingByButton = true);
                      try {
                final t = _ctrl.text.trim();
                if (t.length >= 2) {
                  await search.performSearch(t);
                } else {
                  widget.onOpenFullSearch();
                }
                      } finally {
                        if (mounted) setState(() => _searchingByButton = false);
                      }
                    },
            ),
            IconButton(
              tooltip: 'بحث متقدّم',
              icon: Icon(Icons.open_in_new_rounded, color: AppColors.heading.withValues(alpha: 0.55)),
              onPressed: widget.onOpenFullSearch,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer لشبكة نتائج البحث/التصفية أثناء انتظار Firestore.
class _SearchResultsGridShimmer extends StatelessWidget {
  const _SearchResultsGridShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
        children: List.generate(
          6,
          (_) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromotionsStripShimmer extends StatelessWidget {
  const _PromotionsStripShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemBuilder: (_, _) => Container(
          width: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: 3,
      ),
    );
  }
}

/// قسم أفقي بعنوان عربي و«عرض المزيد» (حتى 10 عناصر في السطر).
class _HomeHorizontalProductsSection extends StatelessWidget {
  final StoreController store;
  final String title;
  final List<Product> sourceProducts;

  const _HomeHorizontalProductsSection({
    required this.store,
    required this.title,
    required this.sourceProducts,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = store.filterProductsBySearch(sourceProducts);
    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: EmptyStateWidget(type: EmptyStateType.products),
      );
    }
    final row = filtered.length > 10 ? filtered.sublist(0, 10) : filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
            Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.heading),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ProductsHorizontalSectionPage(
                        title: title,
                        products: filtered,
                      ),
                    ),
                  );
                },
                child: Text('عرض المزيد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: AppColors.accent)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 300,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: row.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => CompactProductCard(store: store, product: row[i]),
          ),
        ),
      ],
    );
  }
}

/// صف واحد من المنتجات من القائمة المحمّلة (مستقر عند اختلاف بيانات أقسام الواجهة).
class _SimpleHomeProductsSection extends StatelessWidget {
  final StoreController store;

  const _SimpleHomeProductsSection({required this.store});

  @override
  Widget build(BuildContext context) {
    final list = store.products;
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: EmptyStateWidget(type: EmptyStateType.products),
      );
    }
    final shown = list.length > 30 ? list.sublist(0, 30) : list;
    return SizedBox(
      height: 300,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => CompactProductCard(store: store, product: shown[i]),
      ),
    );
  }
}

/// بانر عروض ديناميكي بين الأقسام و«تسوق سريع».
class _PromoDealsCarousel extends StatelessWidget {
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final int activeIndex;

  const _PromoDealsCarousel({
    required this.controller,
    required this.onPageChanged,
    required this.activeIndex,
  });

  static const _slides = <({String title, String subtitle, List<Color> gradient})>[
    (
      title: 'خصومات الأدوات الصحية',
      subtitle: 'تصل إلى 30% على تشكيلة مختارة',
      gradient: [Color(0xFFE8A078), Color(0xFFF2C4A8)],
    ),
    (
      title: 'دهانات الجدران',
      subtitle: 'تشكيلة جديدة بأسعار مميزة',
      gradient: [Color(0xFFD4895F), Color(0xFFE8A078)],
    ),
    (
      title: 'لوازم السباكة والأدوات',
      subtitle: 'جودة عالية وتوصيل سريع',
      gradient: [Color(0xFFB87A5A), Color(0xFFD9A088)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w > 600 ? 24.0 : 16.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: w > 500 ? 150 : 132,
            child: PageView.builder(
              controller: controller,
              onPageChanged: onPageChanged,
              itemCount: _slides.length,
              itemBuilder: (context, i) {
                final s = _slides[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    elevation: 1,
                    shadowColor: AppColors.shadow,
                    borderRadius: BorderRadius.circular(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: s.gradient,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              s.title,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(blurRadius: 8, color: Colors.black26)],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              s.subtitle,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _slides.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: activeIndex == i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activeIndex == i ? AppColors.accent : AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// يختار بانر ووردبريس (صور بارزة) إن وُجدت، وإلا بانر المنتجات.
class _HomeHeroBanner extends StatefulWidget {
  final StoreController store;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final int bannerIndex;

  const _HomeHeroBanner({
    required this.store,
    required this.controller,
    required this.onPageChanged,
    required this.bannerIndex,
  });

  @override
  State<_HomeHeroBanner> createState() => _HomeHeroBannerState();
}

class _HomeHeroBannerState extends State<_HomeHeroBanner> {
  @override
  void didUpdateWidget(covariant _HomeHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final w = widget.store.wpHomeBanners;
    final ow = oldWidget.store.wpHomeBanners;
    final useWp = w.isNotEmpty;
    final useOld = ow.isNotEmpty;
    if (useWp != useOld || (useWp && w.length != ow.length)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.hasClients) {
          widget.controller.jumpToPage(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = widget.store.wpHomeBanners;
    if (wp.isNotEmpty) {
      return _WpHeroBanner(
        slides: wp,
        controller: widget.controller,
        onPageChanged: widget.onPageChanged,
        bannerIndex: widget.bannerIndex,
      );
    }
    return _ProductFallbackHeroBanner(
      store: widget.store,
      controller: widget.controller,
      onPageChanged: widget.onPageChanged,
      bannerIndex: widget.bannerIndex,
    );
  }
}

/// سلايدر صور من Firestore **`home_banners`**. تمرير تلقائي كل 6 ثوانٍ.
class _WpHeroBanner extends StatefulWidget {
  final List<WpHomeBannerSlide> slides;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final int bannerIndex;

  const _WpHeroBanner({
    required this.slides,
    required this.controller,
    required this.onPageChanged,
    required this.bannerIndex,
  });

  @override
  State<_WpHeroBanner> createState() => _WpHeroBannerState();
}

class _WpHeroBannerState extends State<_WpHeroBanner> {
  Timer? _autoTimer;

  List<WpHomeBannerSlide> get _slidesTop3 =>
      widget.slides.length > 3 ? widget.slides.sublist(0, 3) : widget.slides;

  void _restartAutoPlay(int slideCount) {
    _autoTimer?.cancel();
    if (slideCount <= 1) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !widget.controller.hasClients) return;
      final page = widget.controller.page?.round() ?? widget.bannerIndex;
      final next = (page + 1) % slideCount;
      widget.controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.slides.length > 1) _restartAutoPlay(widget.slides.length);
    });
  }

  @override
  void didUpdateWidget(covariant _WpHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.slides.length != oldWidget.slides.length && widget.slides.length > 1) {
      _restartAutoPlay(widget.slides.length);
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slidesTop3;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: _kHomeBannerAspectRatio,
          child: PageView.builder(
            controller: widget.controller,
            onPageChanged: (i) {
              widget.onPageChanged(i);
              _restartAutoPlay(slides.length);
            },
            itemCount: slides.length,
            itemBuilder: (_, i) {
              final s = slides[i];
              final url = webSafeImageUrl(s.imageUrl);
              if (url.isEmpty) {
                final emptyBanner = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Colors.white,
                    elevation: 8,
                    shadowColor: AppColors.orange.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(_kHomeBannerRadius),
                    clipBehavior: Clip.antiAlias,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(_kHomeBannerRadius),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return AmmarJoPageBannerFallback(
                            page: AmmarJoBannerPage.home,
                            height: constraints.maxHeight,
                            borderRadius: _kHomeBannerRadius,
                          );
                        },
                      ),
                    ),
                  ),
                );
                if (s.linkUrl != null && s.linkUrl!.isNotEmpty) {
                  return GestureDetector(
                    onTap: () => _openLink(s.linkUrl!),
                    behavior: HitTestBehavior.opaque,
                    child: emptyBanner,
                  );
                }
                return emptyBanner;
              }
              final image = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.white,
                  elevation: 8,
                  shadowColor: AppColors.orange.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(_kHomeBannerRadius),
                  clipBehavior: Clip.antiAlias,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kHomeBannerRadius),
                    child: ColoredBox(
                      color: Colors.white,
                      child: Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Image.network(
                              url,
                              key: ValueKey<String>('hb_${s.imageUrl}_${s.title ?? ''}'),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => ColoredBox(
                                color: Colors.white,
                                child: Icon(Icons.image_not_supported_outlined, color: AppColors.orange, size: 48),
                              ),
                            ),
                          ),
                          if (s.title != null && s.title!.isNotEmpty)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.72),
                                    ],
                                  ),
                                ),
                                child: Text(
                                  s.title!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                    shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              if (s.linkUrl != null && s.linkUrl!.isNotEmpty) {
                return GestureDetector(
                  onTap: () => _openLink(s.linkUrl!),
                  behavior: HitTestBehavior.opaque,
                  child: image,
                );
              }
              return image;
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: widget.bannerIndex == i ? 26 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.bannerIndex == i ? AppColors.orange : AppColors.navy.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
                boxShadow: widget.bannerIndex == i
                    ? [BoxShadow(color: AppColors.orange.withValues(alpha: 0.45), blurRadius: 8)]
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// احتياطي عند عدم وجود بانرات Firestore: منتجات من الكتالوج؛ تمرير تلقائي.
class _ProductFallbackHeroBanner extends StatefulWidget {
  final StoreController store;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final int bannerIndex;

  const _ProductFallbackHeroBanner({
    required this.store,
    required this.controller,
    required this.onPageChanged,
    required this.bannerIndex,
  });

  @override
  State<_ProductFallbackHeroBanner> createState() => _ProductFallbackHeroBannerState();
}

class _ProductFallbackHeroBannerState extends State<_ProductFallbackHeroBanner> {
  Timer? _autoTimer;

  static List<Product> _itemsForBanner(StoreController store) {
    final fromFeatured = store.bannerProducts.where((p) => p.images.isNotEmpty).take(3).toList();
    if (fromFeatured.isNotEmpty) return fromFeatured;
    final fallback = store.products.where((p) => p.images.isNotEmpty).take(3).toList();
    return fallback;
  }

  void _restartAutoPlay(int slideCount) {
    _autoTimer?.cancel();
    if (slideCount <= 1) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !widget.controller.hasClients) return;
      final page = widget.controller.page?.round() ?? widget.bannerIndex;
      final next = (page + 1) % slideCount;
      widget.controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n = _itemsForBanner(widget.store).length;
      if (n == 0) return;
      _restartAutoPlay(n);
    });
  }

  @override
  void didUpdateWidget(covariant _ProductFallbackHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final n = _itemsForBanner(widget.store).length;
    final o = _itemsForBanner(oldWidget.store).length;
    if (n != o && n > 0) _restartAutoPlay(n);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = _itemsForBanner(widget.store);
    final showFeaturedBadge = widget.store.bannerProducts.isNotEmpty;
    final slides = products.isEmpty
        ? List<Widget>.generate(3, (i) => _bannerPlaceholder(i))
        : products
            .take(3)
            .map((p) => _premiumBannerSlide(p, widget.store, showFeaturedBadge: showFeaturedBadge))
            .toList();

    return Column(
      children: [
        AspectRatio(
          aspectRatio: _kHomeBannerAspectRatio,
          child: PageView.builder(
            controller: widget.controller,
            onPageChanged: (i) {
              widget.onPageChanged(i);
              _restartAutoPlay(slides.length);
            },
            itemCount: slides.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: Colors.white,
                elevation: 8,
                shadowColor: AppColors.orange.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(_kHomeBannerRadius),
                clipBehavior: Clip.antiAlias,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kHomeBannerRadius),
                  child: slides[i],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: widget.bannerIndex == i ? 26 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.bannerIndex == i ? AppColors.orange : AppColors.navy.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
                boxShadow: widget.bannerIndex == i
                    ? [BoxShadow(color: AppColors.orange.withValues(alpha: 0.45), blurRadius: 8)]
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _premiumBannerSlide(Product p, StoreController store, {required bool showFeaturedBadge}) {
  final url = webSafeFirstProductImage(p.images);
  return Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Colors.white),
      Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 56),
          child: url.isEmpty
              ? Icon(Icons.image_not_supported_outlined, color: AppColors.orange, size: 48)
              : AmmarCachedImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  productTileStyle: true,
                ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppColors.orange.withValues(alpha: 0.88),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  shadows: [Shadow(blurRadius: 12, color: Colors.black45)],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  store.formatPrice(p.price),
                  style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
      if (showFeaturedBadge)
        Positioned(
          top: 14,
          right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, color: AppColors.orange, size: 18),
                const SizedBox(width: 4),
                Text(
                  'مميز',
                  style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

Widget _bannerPlaceholder(int index) {
  final colors = [AppColors.orange, AppColors.orangeDark, const Color(0xFFFF8F65)];
  return Container(
    color: colors[index % colors.length].withValues(alpha: 0.85),
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_offer_rounded, color: Colors.white.withValues(alpha: 0.95), size: 48),
          const SizedBox(height: 12),
          Text('عروض وخصومات', style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );
}

class _CategoriesSection extends StatelessWidget {
  final StoreController store;
  const _CategoriesSection({required this.store});

  static const double _chipImageSize = 72;

  @override
  Widget build(BuildContext context) {
    final mains = MainCategoryHierarchy.ordered;
    final mid = (mains.length / 2).ceil();
    final row1 = mains.sublist(0, mid);
    final row2 = mains.sublist(mid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('تسوق حسب القسم', style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.heading)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: row1.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _HomeMainCategoryChip(store: store, main: row1[i], imageSize: _chipImageSize),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: row2.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _HomeMainCategoryChip(store: store, main: row2[i], imageSize: _chipImageSize),
          ),
        ),
      ],
    );
  }
}

class _HomeMainCategoryChip extends StatelessWidget {
  final StoreController store;
  final MainCategoryDefinition main;
  final double imageSize;

  const _HomeMainCategoryChip({required this.store, required this.main, required this.imageSize});

  @override
  Widget build(BuildContext context) {
    final pool = productsForMainCategory(store.products, main);
    final safe = pool.isNotEmpty ? webSafeFirstProductImage(pool.first.images) : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => MainCategoryDetailPage(main: main)),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              Container(
                width: imageSize,
                height: imageSize,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: const Offset(0, 2))],
                ),
                clipBehavior: Clip.antiAlias,
                child: safe.isEmpty
                    ? Icon(Icons.category_outlined, color: AppColors.accent, size: 34)
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: AmmarCachedImage(
                          imageUrl: safe,
                          key: ValueKey<String>('mchip_${main.id}_$safe'),
                          fit: BoxFit.contain,
                          productTileStyle: true,
                        ),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                main.titleAr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 11, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.heading),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
