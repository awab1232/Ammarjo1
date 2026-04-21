import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/contracts/feature_state.dart';
import '../../../core/data/repositories/product_repository.dart';
import '../../../core/widgets/feature_state_builder.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/seo/seo_routes.dart';
import '../../../core/seo/seo_service.dart';
import '../../../core/utils/web_image_url.dart';
import '../../../core/widgets/ammar_cached_image.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../../../core/widgets/home_page_shimmers.dart';
import '../../../core/widgets/premium_categories_strip.dart';
import '../../store/domain/wp_home_banner.dart';
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
import 'widgets/stores_search_product_tile.dart';
import '../../tenders/presentation/pages/tender_request_screen.dart';

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
  int _categoriesRetryKey = 0;
  String _selectedStoreCategoryName = '';
  String? _selectedStoreTypeId;
  List<StoreTypeModel> _storeTypes = const <StoreTypeModel>[];

  /// Stable future for [FutureBuilder] so each rebuild does not restart requests.
  String _storesFetchKey = '';
  Future<FeatureState<List<StoreModel>>>? _storesFetchMemo;

  /// Incremented to invalidate [StoresRepository.fetchApprovedStores] (retry / pull).
  int _storesReloadNonce = 0;

  bool get _hasSearchQuery => _searchController.text.trim().isNotEmpty;

  Widget safeHome(Widget child) {
    try {
      return child;
    } on Object catch (e) {
      debugPrint('HOME BUILD CRASH: $e');
      return const Scaffold(
        body: Center(child: Text('حدث خطأ في العرض')),
      );
    }
  }

  void _refreshCategories() => setState(() => _categoriesRetryKey++);

  /// Single scroll surface (ListView) — avoids nested sliver / scroll overlap on Android.
  Widget _buildHomeStoreDirectoryList(
    BuildContext context,
    StoreController storeController,
    Future<FeatureState<List<StoreModel>>> storeFut,
  ) {
    return FutureBuilder<FeatureState<List<StoreModel>>>(
      future: storeFut,
      builder: (context, storeSnap) {
        if (storeSnap.connectionState == ConnectionState.waiting && !storeSnap.hasData) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
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
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            const SizedBox(height: 4),
            SizedBox(
              height: 218,
              child: _StoresHomePageBannerCarousel(page: widget.homeBannersPageKey),
            ),
            if (widget.storeCategoryFilter == null && kIsWeb) ...[
              const StoresHomeMarketingSectionTitle(
                title: 'أقسام المتاجر',
                subtitle: 'تُدار من لوحة التحكم: المتاجر ← الأقسام الرئيسية',
              ),
              const StoresHomeSectionsCardsStrip(),
              const SizedBox(height: 8),
              const StoresHomeMarketingSectionTitle(
                title: 'عروض اليوم',
                subtitle: 'تُعدّل من لوحة التحكم: إدارة البنرات والصفحة الرئيسية',
              ),
              const StoresHomeOffersStrip(),
              const StoresHomeMarketingSectionTitle(title: 'المتاجر الأكثر طلباً'),
              StoresHomeMostRequestedStrip(futureStores: storeFut),
              const StoresHomeBottomMarketingBanner(),
              const SizedBox(height: 12),
            ],
            if (widget.storeCategoryFilter == null) ...[
              SizedBox(
                height: 54,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    ChoiceChip(
                      label: Text('كل الأنواع', style: GoogleFonts.tajawal()),
                      selected: _selectedStoreTypeId == null,
                      onSelected: (_) => setState(() => _selectedStoreTypeId = null),
                    ),
                    const SizedBox(width: 8),
                    ..._storeTypes.map(
                      (type) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(type.name, style: GoogleFonts.tajawal()),
                          selected: _selectedStoreTypeId == type.id,
                          onSelected: (_) => setState(() => _selectedStoreTypeId = type.id),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'التصنيفات',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(Icons.swipe_rounded, size: 14, color: AppColors.primaryOrange.withValues(alpha: 0.85)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'اسحب للاطلاع على كل التصنيفات',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
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
                  key: ValueKey<int>(_categoriesRetryKey),
                  stream: watchActiveStoreCategoriesWithFallback(),
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
                      final fallbackImg = index < kStoresCategoryImageUrls.length
                          ? kStoresCategoryImageUrls[index]
                          : kStoresCategoryImageUrls[0];
                      final imgRaw = cat.imageUrl.trim().isNotEmpty ? cat.imageUrl : fallbackImg;
                      maps.add(<String, dynamic>{
                        'name': cat.name,
                        'imageUrl': webSafeImageUrl(imgRaw),
                      });
                    }
                    return PremiumCategoriesStrip(
                      categories: maps,
                      selectedName: _selectedStoreCategoryName,
                      onSelect: (name, _) {
                        setState(() => _selectedStoreCategoryName = name);
                        Navigator.of(context).pushNamed(SeoRoutes.category(name));
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 10),
                  Text('كل المتاجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
                ],
              ),
            ),
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
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const ApplyStorePage(lockedCategory: null),
                            ),
                          );
                        },
                        child: Text('تقديم طلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (kIsWeb) const _StoresWebInlineFooter(),
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
      FeatureSuccess(:final data) => _groupedStoreListWidgets(context, storeController, data),
      FeatureFailure(:final message) => <Widget>[
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تعذر تحميل المتاجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(message, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _storesReloadNonce++),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                  child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
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
                Text('تعذر الاتصال بالخادم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => setState(() => _storesReloadNonce++),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                  child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
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
    final showRegionalEmpty = userCity != null && userCity.isNotEmpty && all.isEmpty;
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
                MaterialPageRoute<void>(builder: (_) => const CustomerDeliverySettingsPage()),
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
    final keys = byCategory.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final cat in keys) {
      final list = byCategory[cat]!;
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            cat,
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
          ),
        ),
      );
      for (final s in list) {
        out.add(
          StoreCard(
            store: s,
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => StoreDetailPage(store: s)),
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
          hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 15),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryOrange),
          suffixIcon: _hasSearchQuery
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.6))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primaryOrange, width: 1.5)),
        ),
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
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'جاري تحميل النتائج…',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textSecondary),
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
        final stores = allStores.where((s) => s.name.toLowerCase().contains(q)).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'المتاجر',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
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
                      MaterialPageRoute<void>(builder: (_) => StoreDetailPage(store: s)),
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

  int _getSearchCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 5;
    if (width > 900) return 4;
    if (width > 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    SeoService.apply(SeoService.homeFallback, updatePath: true);
    final storeController = context.watch<StoreController>();
    final city = storeController.profile?.city?.trim();
    final storeKey = '${city ?? ''}|${widget.storeCategoryFilter}|$_selectedStoreTypeId|$_storesReloadNonce';
    if (_storesFetchKey != storeKey) {
      _storesFetchKey = storeKey;
      _storesFetchMemo = StoresRepository.instance.fetchApprovedStores(
        city: city,
        category: widget.storeCategoryFilter,
        storeTypeId: _selectedStoreTypeId,
      );
    }
    final storeListFuture = _storesFetchMemo!;

    return safeHome(Scaffold(
      backgroundColor: AppColors.background,
      extendBody: false,
      appBar: AppBar(
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        leading: widget.onOpenDrawer != null
            ? IconButton(icon: const Icon(Icons.menu_rounded), onPressed: widget.onOpenDrawer)
            : null,
        title: Text(widget.appBarTitle, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: Colors.white)),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _buildSearchField(),
          if (kIsWeb) const _WebAppDownloadBanner(),
          const SizedBox(height: 8),
          Expanded(
            child: _hasSearchQuery
                ? _buildSearchResults(context, storeController, storeListFuture)
                : _buildHomeStoreDirectoryList(context, storeController, storeListFuture),
          ),
        ],
      ),
      floatingActionButton: buildTenderFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    ));
  }
}

class _WebAppDownloadBanner extends StatelessWidget {
  const _WebAppDownloadBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(colors: [Color(0xFF1F2937), Color(0xFF111827)]),
      ),
      child: Row(
        children: [
          const Icon(Icons.download_for_offline_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'حمّل تطبيق AmmarJo لتجربة أسرع وتنبيهات مباشرة للعروض والطلبات',
              style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange, foregroundColor: Colors.white),
            onPressed: () => _open('https://play.google.com/store'),
            child: Text('تحميل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

class _StoresWebInlineFooter extends StatelessWidget {
  const _StoresWebInlineFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      color: Colors.grey.shade100,
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        runSpacing: 18,
        spacing: 18,
        children: [
          _footerColumn(
            context,
            'عن AmmarJo',
            const [('من نحن', '/about'), ('مدونتنا', '/blog')],
          ),
          _footerColumn(
            context,
            'القوانين',
            const [
              ('سياسة الخصوصية', '/privacy'),
              ('شروط الاستخدام', '/terms'),
              ('سياسة الاسترجاع', '/return-policy'),
            ],
          ),
          Container(
            width: 320,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF8A3D), Color(0xFFFF6B00)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('حمّل تطبيق AmmarJo', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text('إشعارات أسرع + عروض حصرية + تجربة أفضل', style: GoogleFonts.tajawal(color: Colors.white.withValues(alpha: 0.95), fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primaryOrange),
                      onPressed: () => _open('https://play.google.com/store'),
                      icon: const Icon(Icons.android_rounded, size: 18),
                      label: Text('Google Play', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primaryOrange),
                      onPressed: () => _open('https://www.apple.com/app-store/'),
                      icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                      label: Text('App Store', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerColumn(BuildContext context, String title, List<(String, String)> links) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...links.map(
          (l) => TextButton(
            onPressed: () => Navigator.of(context).pushNamed(l.$2),
            child: Text(l.$1, style: GoogleFonts.tajawal()),
          ),
        ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

/// بانرات الصفحة من واجهة REST (`fetchHomeBanners`) — تخزين مؤقت، تمرير سلس، ومؤشر صفحات.
class _StoresHomePageBannerCarousel extends StatefulWidget {
  const _StoresHomePageBannerCarousel({required this.page});

  /// مفتاح `page` في إعدادات البنرات (للتوسعة لاحقاً حسب القسم).
  final String page;

  @override
  State<_StoresHomePageBannerCarousel> createState() => _StoresHomePageBannerCarouselState();
}

class _StoresHomePageBannerCarouselState extends State<_StoresHomePageBannerCarousel> {
  Future<FeatureState<List<WpHomeBannerSlide>>>? _future;
  PageController? _pageController;
  double? _viewportFraction;
  Timer? _autoTimer;
  int _bannerIndex = 0;
  int _autoScheduledForCount = -1;

  Future<FeatureState<List<WpHomeBannerSlide>>> _safeFetchBanners({bool forceRefresh = false}) async {
    try {
      final state = await context.read<ProductRepository>().fetchHomeBanners(forceRefresh: forceRefresh);
      return switch (state) {
        FeatureSuccess<List<WpHomeBannerSlide>>(:final data) => FeatureState.success(data),
        _ => FeatureState.success(const <WpHomeBannerSlide>[]),
      };
    } on Object catch (e) {
      debugPrint('[StoresHomePageBannerCarousel] safe fetch failed: $e');
      return FeatureState.success(const <WpHomeBannerSlide>[]);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _safeFetchBanners();
    _ensurePageController();
  }

  @override
  void didUpdateWidget(covariant _StoresHomePageBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page != widget.page) {
      _cancelAuto();
      _autoScheduledForCount = -1;
      _bannerIndex = 0;
      _future = _safeFetchBanners(forceRefresh: true);
    }
  }

  void _ensurePageController() {
    final width = MediaQuery.sizeOf(context).width;
    final vf = width >= 1200 ? 1.0 : 0.92;
    if (_viewportFraction != vf) {
      _viewportFraction = vf;
      _pageController?.dispose();
      _pageController = PageController(viewportFraction: vf);
      _bannerIndex = 0;
      _autoScheduledForCount = -1;
      _cancelAuto();
    }
  }

  void _cancelAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void _scheduleAutoAdvance(int count) {
    _cancelAuto();
    if (count <= 1) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      final pc = _pageController;
      if (!mounted || pc == null || !pc.hasClients) return;
      final cur = pc.page?.round() ?? _bannerIndex;
      final next = (cur + 1) % count;
      pc.animateToPage(
        next,
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _reloadBanners() {
    setState(() {
      _future = _safeFetchBanners(forceRefresh: true);
      _bannerIndex = 0;
      _autoScheduledForCount = -1;
      _cancelAuto();
    });
  }

  @override
  void dispose() {
    _cancelAuto();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _openSlideLink(String? raw) async {
    final u = raw?.trim() ?? '';
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget safeBanner(List<WpHomeBannerSlide> banners, PageController pc) {
    try {
      debugPrint('BANNERS COUNT: ${banners.length}');
      if (banners.isEmpty) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 196,
            child: PageView.builder(
              controller: pc,
              itemCount: banners.length,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) => setState(() => _bannerIndex = i),
              itemBuilder: (context, i) {
                final slide = banners[i];
                final url = webSafeImageUrl(slide.imageUrl);
                if (url.isEmpty) return const SizedBox.shrink();
                final link = slide.linkUrl?.trim();
                final hasLink = link != null && link.isNotEmpty;
                final image = safeImage(
                  url,
                  width: double.infinity,
                  height: 196,
                  fit: BoxFit.cover,
                  useShimmerPlaceholder: true,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: hasLink ? () => _openSlideLink(link) : null,
                        child: image,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (banners.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(banners.length, (i) {
                  final active = i == _bannerIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 7,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: active ? AppColors.primaryOrange : AppColors.border.withValues(alpha: 0.85),
                    ),
                  );
                }),
              ),
            ),
        ],
      );
    } on Object catch (e) {
      debugPrint('BANNER ERROR: $e');
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensurePageController();
    final pc = _pageController;
    return SizedBox(
      height: 218,
      child: FutureBuilder<FeatureState<List<WpHomeBannerSlide>>>(
        key: ValueKey<String>(widget.page),
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting || _future == null) {
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
              if (slides.length != _autoScheduledForCount) {
                _autoScheduledForCount = slides.length;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _scheduleAutoAdvance(slides.length);
                });
              }
              if (pc == null) {
                return const HomeBannerSkeleton();
              }
              return safeBanner(slides, pc);
            },
          );
        },
      ),
    );
  }
}

class _StoresHomeBannerUnavailable extends StatelessWidget {
  const _StoresHomeBannerUnavailable({this.onRetry, this.compact = false});

  final VoidCallback? onRetry;
  final bool compact;

  static const String _placeholder = 'https://placehold.co/600x200/e2e8f0/94a3b8/png?text=AmmarJo';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: compact ? 0 : 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 0 : 16),
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
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
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
                      shadows: const [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                  if (onRetry != null && !compact) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(foregroundColor: AppColors.primaryOrange),
                      child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
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
