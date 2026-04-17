import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../../core/widgets/premium_categories_strip.dart';
import '../../store/domain/wp_home_banner.dart';
import '../../store/presentation/pages/customer_delivery_settings_page.dart';
import '../../store/presentation/pages/home_page.dart';
import '../../store/presentation/store_controller.dart';
import '../data/store_categories_repository.dart';
import '../data/stores_repository.dart';
import '../domain/store_model.dart';
import '../data/store_types_repository.dart';
import '../domain/store_type_model.dart';
import 'apply_store_page.dart';
import 'store_detail_page.dart';
import 'widgets/store_card.dart';
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

  bool get _hasSearchQuery => _searchController.text.trim().isNotEmpty;

  void _refreshCategories() => setState(() => _categoriesRetryKey++);

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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        textAlign: TextAlign.right,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'ابحث عن متجر أو منتج…',
          hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, StoreController storeController, String? city) {
    final q = _searchController.text.trim().toLowerCase();
    return FutureBuilder<FeatureState<List<StoreModel>>>(
      future: StoresRepository.instance.fetchApprovedStores(
        city: city,
        category: widget.storeCategoryFilter,
        storeTypeId: _selectedStoreTypeId,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        return buildFeatureStateUi<List<StoreModel>>(
          context: context,
          state: snap.data!,
          dataBuilder: (ctx, allStores) {
        final stores = allStores.where((s) => s.name.toLowerCase().contains(q)).toList();
        final products = storeController.products.where((p) => p.name.toLowerCase().contains(q)).toList();

        final isWebGrid = kIsWeb && MediaQuery.of(context).size.width > 800;
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'المنتجات',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary),
              ),
            ),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: EmptyStateWidget(type: EmptyStateType.search),
              )
            else if (isWebGrid)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _getSearchCrossAxisCount(context),
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, i) {
                    final p = products[i];
                    return StoresSearchProductTile(
                      product: p,
                      storeId: 'ammarjo',
                      storeName: kAmmarJoCatalogStoreName,
                      onProductTap: () {
                        openProductPage(
                          context,
                          product: p,
                          cartStoreId: 'ammarjo',
                          cartStoreName: kAmmarJoCatalogStoreName,
                        );
                      },
                      onVisitStore: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: (_) => const HomePage()),
                        );
                      },
                      onAddToCart: () async {
                        await storeController.addToCart(
                          p,
                          storeId: 'ammarjo',
                          storeName: kAmmarJoCatalogStoreName,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تمت الإضافة للسلة', style: GoogleFonts.tajawal())),
                          );
                        }
                      },
                    );
                  },
                ),
              )
            else
              ...products.map(
                (p) => StoresSearchProductTile(
                  product: p,
                  storeId: 'ammarjo',
                  storeName: kAmmarJoCatalogStoreName,
                  onProductTap: () {
                    openProductPage(
                      context,
                      product: p,
                      cartStoreId: 'ammarjo',
                      cartStoreName: kAmmarJoCatalogStoreName,
                    );
                  },
                  onVisitStore: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const HomePage()),
                    );
                  },
                  onAddToCart: () async {
                    await storeController.addToCart(
                      p,
                      storeId: 'ammarjo',
                      storeName: kAmmarJoCatalogStoreName,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تمت الإضافة للسلة', style: GoogleFonts.tajawal())),
                      );
                    }
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

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: false,
      appBar: AppBar(
        backgroundColor: AppColors.primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
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
                ? _buildSearchResults(context, storeController, city)
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(child: SizedBox(height: 4)),
                      SliverToBoxAdapter(
                        child: _StoresHomePageBannerCarousel(page: widget.homeBannersPageKey),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 20)),
                      if (widget.storeCategoryFilter == null) ...[
                        SliverToBoxAdapter(
                          child: SizedBox(
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
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        SliverToBoxAdapter(
                          child: Padding(
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
                                    Text(
                                      'اسحب للاطلاع على كل التصنيفات',
                                      style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 10)),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: StreamBuilder<FeatureState<List<StoreCategoryEntry>>>(
                              key: ValueKey<int>(_categoriesRetryKey),
                              stream: watchActiveStoreCategoriesWithFallback(),
                              builder: (context, catSnap) {
                                if (catSnap.hasError) {
                                  debugPrint('Store categories (builder) error: ${catSnap.error}');
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'حدث خطأ في تحميل التصنيفات',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                                          ),
                                          const SizedBox(height: 12),
                                          FilledButton(
                                            onPressed: _refreshCategories,
                                            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                                            child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                final cats = switch (catSnap.data) {
                                  FeatureSuccess(:final data) => data,
                                  _ => const <StoreCategoryEntry>[],
                                };
                                if (cats.isEmpty) {
                                  return const SizedBox.shrink();
                                }
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
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ] else
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Container(
                                  width: 4,
                                  height: 22,
                                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2))),
                              const SizedBox(width: 10),
                              Text('المتاجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      SliverToBoxAdapter(
                        child: FutureBuilder<FeatureState<List<StoreModel>>>(
                          future: StoresRepository.instance.fetchApprovedStores(
                                city: city,
                                category: widget.storeCategoryFilter,
                                storeTypeId: _selectedStoreTypeId,
                              ),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            if (!snap.hasData) {
                              return const SizedBox.shrink();
                            }
                            return buildFeatureStateUi<List<StoreModel>>(
                              context: context,
                              state: snap.data!,
                              dataBuilder: (ctx, allStores) {
                            var all = List<StoreModel>.from(allStores);
                            all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                            final rest = all.where((s) => s.id.toLowerCase().trim() != 'ammarjo').toList();
                            final userCity = storeController.profile?.city?.trim();
                            final showRegionalEmpty = userCity != null && userCity.isNotEmpty && all.isEmpty;
                            final showAmmarJoRow = widget.storeCategoryFilter == null;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showAmmarJoRow)
                                  StoreCard(
                                    store: ammarJoCatalogStoreModel(),
                                    onTap: () {
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(builder: (_) => const HomePage()),
                                      );
                                    },
                                  ),
                                if (!kIsWeb && !showRegionalEmpty && rest.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                    child: Row(
                                      children: [
                                        const Expanded(child: Divider()),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          child: Text('متاجر أخرى', style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13)),
                                        ),
                                        const Expanded(child: Divider()),
                                      ],
                                    ),
                                  ),
                                ],
                                if (showRegionalEmpty)
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
                                  )
                                else
                                  ...rest.map(
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
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      SliverToBoxAdapter(
                        child: Padding(
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
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primaryOrange,
                                      side: const BorderSide(color: AppColors.primaryOrange, width: 1.5),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) => ApplyStorePage(
                                            lockedCategory: null,
                                          ),
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
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      if (kIsWeb) const SliverToBoxAdapter(child: _StoresWebInlineFooter()),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: buildTenderFab(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
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

/// بانرات الصفحة من واجهة REST (`fetchHomeBanners`).
class _StoresHomePageBannerCarousel extends StatelessWidget {
  const _StoresHomePageBannerCarousel({required this.page});

  final String page;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: FutureBuilder<FeatureState<List<WpHomeBannerSlide>>>(
        future: context.read<ProductRepository>().fetchHomeBanners(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)));
          }
          if (!snap.hasData) {
            return const _StoresHomeBannerUnavailable();
          }
          return buildFeatureStateUi<List<WpHomeBannerSlide>>(
            context: context,
            state: snap.data!,
            dataBuilder: (ctx, slides) {
              if (slides.isEmpty) {
                return const _StoresHomeBannerUnavailable();
              }
              final width = MediaQuery.of(context).size.width;
              final desktop = width >= 1200;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: PageView.builder(
                  controller: PageController(viewportFraction: desktop ? 1.0 : 0.92),
                  itemCount: slides.length,
                  itemBuilder: (context, i) {
                    final raw = slides[i].imageUrl;
                    final url = webSafeImageUrl(raw);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: url.isEmpty
                            ? const _StoresHomeBannerUnavailable()
                            : AmmarCachedImage(
                                imageUrl: url,
                                width: double.infinity,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _StoresHomeBannerUnavailable extends StatelessWidget {
  const _StoresHomeBannerUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Service temporarily unavailable',
        style: GoogleFonts.tajawal(color: AppColors.textSecondary),
      ),
    );
  }
}
