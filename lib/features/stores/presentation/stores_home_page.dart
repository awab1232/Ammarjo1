import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/contracts/feature_state.dart';
import '../../../core/data/repositories/product_repository.dart';
import '../../../core/widgets/feature_state_builder.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/seo/seo_service.dart';
import '../../../core/utils/web_image_url.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/home_page_shimmers.dart';
import '../../../core/widgets/premium_categories_strip.dart';
import '../../store/domain/home_banner_slide.dart';
import '../../store/presentation/pages/customer_delivery_settings_page.dart';
import '../../store/presentation/store_controller.dart';
import '../data/store_categories_repository.dart';
import '../data/stores_repository.dart';
import '../domain/store_model.dart';
import '../data/store_types_repository.dart';
import '../domain/store_type_model.dart';
import 'apply_store_page.dart';
import 'store_detail_page.dart';
import 'widgets/store_card.dart';
import 'widgets/stores_home_marketing_sections.dart';
import '../../tenders/presentation/pages/tender_request_screen.dart';
import 'pages/category_page.dart';

/// صور تصنيفات (شبكة المتاجر) — روابط ثابتة لعرض حقيقي.
const List<String> kStoresCategoryImageUrls = <String>[
  'https://images.unsplash.com/photo-1541888946425-d81bb19240f5?w=600&q=80',
  'https://images.unsplash.com/photo-1621905252507-b35492cc74b4?w=600&q=80',
  'https://images.unsplash.com/photo-1589939705384-5185137a7f0f?w=600&q=80',
  'https://images.unsplash.com/photo-1585704031112-1a95f6ecd6db?w=600&q=80',
  'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=600&q=80',
  'https://images.unsplash.com/photo-1615873968403-89e068629265?w=600&q=80',
  'https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=600&q=80',
  'https://images.unsplash.com/photo-1504148455328-c376907d081c?w=600&q=80',
];

/// مستوى ١ — بانرات، سلايدر، شبكة تصنيفات، ومتاجر مميزة.
/// (بما فيها تبويب «أدوات منزلية» عند [storeCategoryFilter]؛ الطلبات والتتبع عبر نفس مسار المتجر الموحّد.)
class StoresHomePage extends StatefulWidget {
  const StoresHomePage({
    super.key,
    this.onOpenDrawer,
    this.storeCategoryFilter,
    this.appBarTitle = 'المتاجر',
    this.homeBannersPageKey = 'stores',
  });

  final VoidCallback? onOpenDrawer;

  /// عند تعيينه (مثل [StoreCategoryKind.homeTools]) تُعرض فقط المتاجر ذات هذا التصنيف.
  final String? storeCategoryFilter;

  final String appBarTitle;

  /// مفتاح `page` في `home_banners` (مثل `stores` أو `home_tools`).
  final String homeBannersPageKey;

  @override
  State<StoresHomePage> createState() => _StoresHomePageState();
}

class _StoresHomePageState extends State<StoresHomePage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedStoreCategoryName = '';
  String? _selectedStoreTypeId;
  List<StoreTypeModel> _storeTypes = const <StoreTypeModel>[];

  /// Stable future for [FutureBuilder] so each rebuild does not restart requests.
  String _storesFetchKey = '';
  Future<FeatureState<List<StoreModel>>>? _storesFetchMemo;
  late Stream<FeatureState<List<StoreCategoryEntry>>> _categoriesStream;

  /// Incremented to invalidate [StoresRepository.fetchApprovedStores] (retry / pull).
  int _storesReloadNonce = 0;

  bool get _hasSearchQuery => _searchController.text.trim().isNotEmpty;

  Widget safeHome(Widget child) {
    try {
      return child;
    } on Object catch (e) {
      debugPrint('HOME BUILD CRASH: $e');
      return const Scaffold(body: Center(child: Text('حدث خطأ في العرض')));
    }
  }

  /// Single scroll surface (ListView) — avoids nested sliver / scroll overlap on Android.
  Widget _buildHomeStoreDirectoryList(
    BuildContext context,
    StoreController storeController,
    Future<FeatureState<List<StoreModel>>> storeFut,
  ) {
    return FutureBuilder<FeatureState<List<StoreModel>>>(
      future: storeFut,
      builder: (context, storeSnap) {
        if (storeSnap.connectionState == ConnectionState.waiting &&
            !storeSnap.hasData) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: const [
              SizedBox(height: 4),
              SizedBox(height: 218, child: HomeBannerSkeleton()),
              SizedBox(height: 16),
              HomeStoreListSkeleton(rows: 5),
            ],
          );
        }
        if (storeSnap.hasError) {
          debugPrint('HOME ERROR: ${storeSnap.error}');
          return const SizedBox.shrink();
        }
        if (!storeSnap.hasData) {
          return const SizedBox.shrink();
        }
        debugPrint('HOME DATA LOADED');
        final st = storeSnap.data!;
        final bottomPad = MediaQuery.paddingOf(context).bottom + 24;
        return ListView(
          padding: EdgeInsets.only(bottom: bottomPad),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            const SizedBox(height: 4),
            SizedBox(
              height: 218,
              child: _StoresHomePageBannerCarousel(
                page: widget.homeBannersPageKey,
              ),
            ),
            if (widget.storeCategoryFilter == null) ...[
              _sectionHeader('أقسام المتاجر'),
              _buildStoreTypeChips(),
              _sectionHeader('التصنيفات'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'التصنيفات',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.swipe_rounded,
                          size: 14,
                          color: AppColors.primaryOrange.withValues(
                            alpha: 0.85,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'اسحب للاطلاع على كل التصنيفات',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.tajawal(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: StreamBuilder<FeatureState<List<StoreCategoryEntry>>>(
                  key: const ValueKey<String>('stores_home_categories'),
                  stream: _categoriesStream,
                  builder: (context, catSnap) {
                    if (catSnap.hasError) {
                      debugPrint('HOME ERROR: ${catSnap.error}');
                      return const SizedBox.shrink();
                    }
                    if (!catSnap.hasData) {
                      return const SizedBox.shrink();
                    }
                    debugPrint('HOME DATA LOADED');
                    final cats = switch (catSnap.data) {
                      FeatureSuccess(:final data) => data,
                      _ => const <StoreCategoryEntry>[],
                    };
                    if (cats.isEmpty) return const SizedBox.shrink();
                    final maps = <Map<String, dynamic>>[];
                    for (var index = 0; index < cats.length; index++) {
                      final cat = cats[index];
                      final fallbackImg =
                          index < kStoresCategoryImageUrls.length
                          ? kStoresCategoryImageUrls[index]
                          : kStoresCategoryImageUrls[0];
                      final imgRaw = cat.imageUrl.trim().isNotEmpty
                          ? cat.imageUrl
                          : fallbackImg;
                      maps.add(<String, dynamic>{
                        'id': cat.id,
                        'name': cat.name,
                        'imageUrl': webSafeImageUrl(imgRaw),
                      });
                    }
                    return PremiumCategoriesStrip(
                      categories: maps,
                      selectedName: _selectedStoreCategoryName,
                      onSelect: (name, _) {
                        setState(() => _selectedStoreCategoryName = name);
                        final category = cats.firstWhere(
                          (c) => c.name == name,
                          orElse: () => cats.first,
                        );
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => CategoryPage(
                              categoryId: category.id,
                              categoryName: category.name,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _sectionHeader('عروض اليوم'),
              const StoresHomeOffersStrip(),
              _sectionHeader('أعلى المتاجر تقييماً'),
              const StoresHomeTopRatedStrip(),
            ] else ...[
              const SizedBox(height: 8),
            ],
            _sectionHeader('جميع المتاجر'),
            const SizedBox(height: 8),
            ..._buildHomeStoreRowsFromState(context, storeController, st),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'هل أنت صاحب متجر؟ انضم إلينا',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const ApplyStorePage(lockedCategory: null),
                            ),
                          );
                        },
                        child: Text(
                          'تقديم طلب',
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 60),
          ],
        );
      },
    );
  }

  List<Widget> _buildHomeStoreRowsFromState(
    BuildContext context,
    StoreController storeController,
    FeatureState<List<StoreModel>> st,
  ) {
    return switch (st) {
      FeatureSuccess(:final data) => _groupedStoreListWidgets(
        context,
        storeController,
        data,
      ),
      FeatureFailure(:final message) => <Widget>[
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تعذر تحميل المتاجر',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.tajawal(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _storesReloadNonce++),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                ),
                child: Text(
                  'إعادة المحاولة',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
      FeatureCriticalPublicDataFailure() => <Widget>[
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تعذر الاتصال بالخادم',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => setState(() => _storesReloadNonce++),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryOrange,
                ),
                child: Text(
                  'إعادة المحاولة',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
      _ => <Widget>[
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('المتاجر غير متاحة', style: GoogleFonts.tajawal()),
        ),
      ],
    };
  }

  List<Widget> _groupedStoreListWidgets(
    BuildContext context,
    StoreController storeController,
    List<StoreModel> allStores,
  ) {
    var all = List<StoreModel>.from(allStores);
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final userCity = storeController.profile?.city?.trim();
    final showRegionalEmpty =
        userCity != null && userCity.isNotEmpty && all.isEmpty;
    final out = <Widget>[];
    if (showRegionalEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: EmptyStateWidget(
            type: EmptyStateType.stores,
            customTitle: 'لا توجد متاجر في منطقتك',
            onAction: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const CustomerDeliverySettingsPage(),
                ),
              );
            },
            actionLabel: 'تغيير المنطقة',
          ),
        ),
      );
      return out;
    }
    final byCategory = <String, List<StoreModel>>{};
    for (final s in all) {
      final key = s.category.trim().isEmpty ? 'أخرى' : s.category.trim();
      byCategory.putIfAbsent(key, () => <StoreModel>[]).add(s);
    }
    final keys = byCategory.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final cat in keys) {
      final list = byCategory[cat]!;
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            cat,
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      );
      for (final s in list) {
        out.add(
          StoreCard(
            store: s,
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => StoreDetailPage(store: s),
                ),
              );
            },
          ),
        );
      }
    }
    if (all.isEmpty && !showRegionalEmpty) {
      out.add(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: EmptyStateWidget(type: EmptyStateType.stores),
        ),
      );
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _categoriesStream = watchActiveStoreCategoriesWithFallback()
        .asBroadcastStream();
    _loadStoreTypes();
  }

  Future<void> _loadStoreTypes() async {
    final state = await StoreTypesRepository.instance.fetchActiveStoreTypes();
    if (!mounted) return;
    switch (state) {
      case FeatureSuccess(:final data):
        setState(() => _storeTypes = data);
      case FeatureFailure():
      case FeatureMissingBackend():
      case FeatureAdminNotWired():
      case FeatureAdminMissingEndpoint():
      case FeatureCriticalPublicDataFailure():
        break;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: TextField(
        controller: _searchController,
        textAlign: TextAlign.right,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'ابحث عن متجر أو منتج…',
          hintStyle: GoogleFonts.tajawal(
            color: AppColors.textSecondary,
            fontSize: 15,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.primaryOrange,
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasSearchQuery)
                IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
              IconButton(
                icon: const Icon(
                  Icons.mic_none_rounded,
                  color: AppColors.primaryOrange,
                ),
                onPressed: () {},
              ),
            ],
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppColors.border.withValues(alpha: 0.6),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppColors.border.withValues(alpha: 0.6),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: AppColors.primaryOrange,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFFE8471A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.tajawal(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                'عرض الكل',
                style: GoogleFonts.tajawal(
                  color: const Color(0xFFE8471A),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStoreTypeChips() {
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _storeTypes.length + 1,
        itemBuilder: (context, i) {
          final isAll = i == 0;
          final selected = isAll
              ? _selectedStoreTypeId == null
              : _selectedStoreTypeId == _storeTypes[i - 1].id;
          final String name = isAll ? 'كل الأنواع' : _storeTypes[i - 1].name;
          final String? imageUrl = isAll
              ? null
              : webSafeImageUrl(_storeTypes[i - 1].image?.trim() ?? '');
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedStoreTypeId = isAll ? null : _storeTypes[i - 1].id;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFE8471A) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? const Color(0xFFE8471A).withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Icon(
                      Icons.storefront_rounded,
                      color: selected ? Colors.white : const Color(0xFFE8471A),
                      size: 28,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: GoogleFonts.tajawal(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    StoreController storeController,
    Future<FeatureState<List<StoreModel>>> storesFuture,
  ) {
    final q = _searchController.text.trim().toLowerCase();
    return FutureBuilder<FeatureState<List<StoreModel>>>(
      future: storesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'جاري تحميل النتائج…',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const HomeStoreListSkeleton(rows: 5),
            ],
          );
        }
        if (snap.hasError) {
          debugPrint('HOME ERROR: ${snap.error}');
          return const SizedBox.shrink();
        }
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        debugPrint('HOME DATA LOADED');
        return buildFeatureStateUi<List<StoreModel>>(
          context: context,
          state: snap.data!,
          onRetry: () => setState(() => _storesReloadNonce++),
          dataBuilder: (ctx, allStores) {
            final stores = allStores
                .where((s) => s.name.toLowerCase().contains(q))
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'المتاجر',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (stores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: EmptyStateWidget(type: EmptyStateType.stores),
                  )
                else
                  ...stores.map(
                    (s) => StoreCard(
                      store: s,
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => StoreDetailPage(store: s),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SeoService.apply(SeoService.homeFallback, updatePath: true);
    final storeController = context.watch<StoreController>();
    final city = storeController.profile?.city?.trim();
    final authMode = storeController.isLoggedIn ? 'authed' : 'public';
    final storeKey =
        '${city ?? ''}|${widget.storeCategoryFilter}|$_selectedStoreTypeId|$_storesReloadNonce|$authMode';
    if (_storesFetchKey != storeKey) {
      _storesFetchKey = storeKey;
      _storesFetchMemo = StoresRepository.instance.fetchApprovedStores(
        city: city,
        category: widget.storeCategoryFilter,
        storeTypeId: _selectedStoreTypeId,
      );
    }
    final storeListFuture = _storesFetchMemo!;

    return safeHome(
      Scaffold(
        backgroundColor: AppColors.background,
        extendBody: false,
        appBar: AppBar(
          backgroundColor: AppColors.primaryOrange,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 1,
          surfaceTintColor: Colors.transparent,
          leading: widget.onOpenDrawer != null
              ? IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: widget.onOpenDrawer,
                )
              : null,
          title: Text(
            widget.appBarTitle,
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _buildSearchField(),
            const SizedBox(height: 8),
            Expanded(
              child: _hasSearchQuery
                  ? _buildSearchResults(
                      context,
                      storeController,
                      storeListFuture,
                    )
                  : _buildHomeStoreDirectoryList(
                      context,
                      storeController,
                      storeListFuture,
                    ),
            ),
          ],
        ),
        floatingActionButton: buildTenderFab(context),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      ),
    );
  }
}

/// بانرات الصفحة من واجهة REST (`fetchHomeBanners`) — تخزين مؤقت، تمرير سلس، ومؤشر صفحات.
class _StoresHomePageBannerCarousel extends StatefulWidget {
  const _StoresHomePageBannerCarousel({required this.page});

  /// مفتاح `page` في إعدادات البنرات (للتوسعة لاحقاً حسب القسم).
  final String page;

  @override
  State<_StoresHomePageBannerCarousel> createState() =>
      _StoresHomePageBannerCarouselState();
}

class _StoresHomePageBannerCarouselState
    extends State<_StoresHomePageBannerCarousel> {
  Future<FeatureState<List<WpHomeBannerSlide>>>? _future;

  Future<FeatureState<List<WpHomeBannerSlide>>> _safeFetchBanners({
    bool forceRefresh = false,
  }) async {
    final state = await context.read<ProductRepository>().fetchHomeBanners(
      forceRefresh: forceRefresh,
    );
    return switch (state) {
      FeatureSuccess<List<WpHomeBannerSlide>>(:final data) =>
        FeatureState.success(data),
      FeatureFailure(:final message, :final cause) => FeatureState.failure(
        message,
        cause,
      ),
      FeatureMissingBackend(:final featureName) => FeatureState.failure(
        'Missing backend: $featureName',
      ),
      FeatureAdminNotWired(:final featureName) => FeatureState.failure(
        'Feature not wired: $featureName',
      ),
      FeatureAdminMissingEndpoint(:final featureName) => FeatureState.failure(
        'Missing endpoint: $featureName',
      ),
      FeatureCriticalPublicDataFailure(:final featureName, :final cause) =>
        FeatureState.failure('Critical failure: $featureName', cause),
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _safeFetchBanners();
  }

  @override
  void didUpdateWidget(covariant _StoresHomePageBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) {
      _future = _safeFetchBanners(forceRefresh: true);
    }
  }

  void _reloadBanners() {
    setState(() {
      _future = _safeFetchBanners(forceRefresh: true);
    });
  }

  @override
  void dispose() => super.dispose();

  Future<void> _openSlideLink(String? raw) async {
    final u = raw?.trim() ?? '';
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget safeBanner(List<WpHomeBannerSlide> banners) {
    try {
      debugPrint('BANNERS COUNT: ${banners.length}');
      if (banners.isEmpty) return const SizedBox.shrink();
      return _PremiumBannerCarousel(
        banners: banners,
        onOpenLink: _openSlideLink,
      );
    } on Object catch (e) {
      debugPrint('BANNER ERROR: $e');
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 218,
      child: FutureBuilder<FeatureState<List<WpHomeBannerSlide>>>(
        key: ValueKey<String>(widget.page),
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting ||
              _future == null) {
            return const HomeBannerSkeleton();
          }
          if (snap.hasError) {
            debugPrint('HOME ERROR: ${snap.error}');
            return const SizedBox.shrink();
          }
          if (!snap.hasData) {
            return const SizedBox.shrink();
          }
          debugPrint('HOME DATA LOADED');
          return buildFeatureStateUi<List<WpHomeBannerSlide>>(
            context: context,
            state: snap.data!,
            onRetry: _reloadBanners,
            dataBuilder: (ctx, slides) {
              if (slides.isEmpty) {
                return _StoresHomeBannerUnavailable(onRetry: _reloadBanners);
              }
              return safeBanner(slides);
            },
          );
        },
      ),
    );
  }
}

class _PremiumBannerCarousel extends StatefulWidget {
  const _PremiumBannerCarousel({
    required this.banners,
    required this.onOpenLink,
  });

  final List<WpHomeBannerSlide> banners;
  final Future<void> Function(String? url) onOpenLink;

  @override
  State<_PremiumBannerCarousel> createState() => _PremiumBannerCarouselState();
}

class _PremiumBannerCarouselState extends State<_PremiumBannerCarousel> {
  late final PageController _pc;
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pc = PageController(viewportFraction: 0.92);
    if (widget.banners.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!_pc.hasClients) return;
        final next = (_current + 1) % widget.banners.length;
        _pc.animateToPage(
          next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pc,
            itemCount: widget.banners.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              final slide = widget.banners[i];
              final imageUrl = webSafeImageUrl(slide.imageUrl);
              final selected = i == _current;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: selected ? 0 : 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: selected ? 1 : 0),
                        duration: const Duration(milliseconds: 350),
                        builder: (context, t, child) {
                          final dx = (1 - t) * 10;
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, error, stackTrace) =>
                              Container(
                                color: const Color(0xFFF5F5F5),
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Color(0xFFE8471A),
                                  size: 42,
                                ),
                              ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.62),
                            ],
                          ),
                        ),
                      ),
                      if ((slide.title ?? '').trim().isNotEmpty)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Text(
                            slide.title!,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.tajawal(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => widget.onOpenLink(slide.linkUrl),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.banners.length, (i) {
            final active = i == _current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? const Color(0xFFE8471A) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _StoresHomeBannerUnavailable extends StatelessWidget {
  const _StoresHomeBannerUnavailable({this.onRetry});

  final VoidCallback? onRetry;

  static const String _placeholder =
      'https://placehold.co/600x200/e2e8f0/94a3b8/png?text=AmmarJo';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.network(
              _placeholder,
              height: 196,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 196,
                color: AppColors.surfaceSecondary,
                alignment: Alignment.center,
                child: Text(
                  'عرض خاص',
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تعذّر تحميل البنرات — عرض بديل',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      shadows: const [
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 4,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        foregroundColor: AppColors.primaryOrange,
                      ),
                      child: Text(
                        'إعادة المحاولة',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
