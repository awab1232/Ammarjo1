import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/data/repositories/user_repository.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/widgets/ammar_cached_image.dart';
import '../../../core/widgets/home_page_shimmers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/jordan_phone.dart';
import '../../../core/utils/web_image_url.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/widgets/full_screen_image_viewer.dart';
import '../../../core/seo/seo_routes.dart';
import '../../../core/seo/seo_service.dart';
import '../../../core/config/chat_feature_config.dart';
import '../../communication/presentation/unified_chat_page.dart';
import '../../reviews/data/reviews_repository.dart';
import '../../reviews/domain/review_model.dart';
import '../../store/presentation/store_controller.dart';
import '../../reviews/presentation/widgets/reviews_section.dart';
import '../data/stores_repository.dart';
import '../domain/store_model.dart';
import '../domain/shipping_policy.dart';
import '../domain/store_shelf_product.dart';
import 'store_category_page.dart';

/// تفاصيل المتجر — غلاف، أقسام، ومنتجات حسب التصنيف.
class StoreDetailPage extends StatefulWidget {
  const StoreDetailPage({super.key, required this.store});

  final StoreModel store;

  @override
  State<StoreDetailPage> createState() => _StoreDetailPageState();
}

class _StoreDetailPageState extends State<StoreDetailPage> {
  String? _selectedCat;
  late final Future<({List<String> categoryNames, List<StoreShelfProduct> products})> _catalogFuture;

  StoreModel get store => widget.store;

  Future<({List<String> categoryNames, List<StoreShelfProduct> products})> _loadCatalog() async {
    final catsState = await StoresRepository.instance.fetchStoreCategoriesMaps(store.id);
    final cats = switch (catsState) {
      FeatureSuccess(:final data) => data,
      FeatureFailure() => <Map<String, dynamic>>[],
      _ => <Map<String, dynamic>>[],
    };
    final productsState = await StoresRepository.instance.fetchStoreShelfProducts(store.id);
    final List<StoreShelfProduct> products = switch (productsState) {
      FeatureSuccess(:final data) => data,
      FeatureMissingBackend() => const <StoreShelfProduct>[],
      FeatureAdminNotWired() => const <StoreShelfProduct>[],
      FeatureAdminMissingEndpoint() => const <StoreShelfProduct>[],
      FeatureCriticalPublicDataFailure() => const <StoreShelfProduct>[],
      FeatureFailure() => const <StoreShelfProduct>[],
    };
    final available = products.where((p) => p.isAvailable).toList();
    final namesFromApi = cats.map((c) => c['name']?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
    final List<String> names;
    if (namesFromApi.isNotEmpty) {
      names = namesFromApi;
    } else {
      names = {for (final p in available) p.shelfCategory.trim()}.where((s) => s.isNotEmpty).toList()..sort();
    }
    return (categoryNames: names, products: available);
  }

  @override
  void initState() {
    super.initState();
    _catalogFuture = _loadCatalog();
  }

  Future<String?> _ownerEmail() async {
    if (!Firebase.apps.isNotEmpty) return null;
    final p = await BackendUserRepository.instance.fetchProfileDocument(store.ownerId);
    return p?.email.trim();
  }

  bool _isOwnStore() {
    final u = FirebaseAuth.instance.currentUser;
    return u != null && u.uid == store.ownerId;
  }

  Future<void> _openChat(BuildContext context) async {
    if (!kChatFeatureEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(kChatFeatureUnavailableMessage, style: GoogleFonts.tajawal())),
      );
      return;
    }
    if (!Firebase.apps.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Firebase غير جاهز', style: GoogleFonts.tajawal())),
      );
      return;
    }

    if (_isOwnStore()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكنك مراسلة متجرك من نفس الحساب.', style: GoogleFonts.tajawal()),
        ),
      );
      return;
    }

    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('يرجى تسجيل الدخول أولاً', style: GoogleFonts.tajawal())),
      );
      return;
    }

    final storeCtrl = context.read<StoreController>();
    final myEmail = storeCtrl.profile?.email.trim() ?? '';
    if (myEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('يلزم بريد مسجل في الملف لبدء المحادثة.', style: GoogleFonts.tajawal())),
      );
      return;
    }

    final ownerEmail = await _ownerEmail();
    if (!context.mounted) return;
    if (ownerEmail == null || ownerEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر العثور على بريد صاحب المتجر.', style: GoogleFonts.tajawal())),
      );
      return;
    }

    if (myEmail.trim().toLowerCase() == ownerEmail.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن الدردشة مع نفسك (نفس البريد).', style: GoogleFonts.tajawal()),
        ),
      );
      return;
    }

    final buyerPhone = dialablePhoneFromProfileEmail(myEmail) ?? '';
    final peerPhone = store.phone.trim();

    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const DialogLoadingPanel(message: 'جاري فتح المحادثة…'),
      );
      final chatId = await ChatService().getOrCreateChat(
        otherUserId: store.ownerId,
        otherUserName: store.name,
        currentUserEmail: myEmail,
        currentUserPhone: buyerPhone,
        otherUserEmail: ownerEmail,
        otherUserPhone: peerPhone,
        chatType: 'store',
        referenceId: store.id,
        referenceName: store.name,
        referenceImageUrl: store.logo.trim().isEmpty ? null : webSafeImageUrl(store.logo),
      );
      if (context.mounted) Navigator.of(context).pop();
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => UnifiedChatPage.resume(
            existingChatId: chatId,
            threadTitle: store.name,
          ),
        ),
      );
    } on Object catch (e, st) {
      debugPrint('StoreDetailPage._openChat: $e\n$st');
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في فتح المحادثة. حاول مرة أخرى.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  Future<void> _openReviewsDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 8),
              Text('تقييمات المتجر', textAlign: TextAlign.center, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 17)),
              ReviewsSection(targetId: store.id, targetType: 'store', title: 'كل المراجعات'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SeoService.apply(
      SeoData(
        title: '${store.name} | AmmarJo',
        description: store.description.trim().isEmpty ? 'Browse products from ${store.name} on AmmarJo.' : store.description,
        keywords: 'AmmarJo, store, ${store.name}',
        path: '/store/${Uri.encodeComponent(store.id)}',
      ),
    );
    final cover = webSafeImageUrl(store.coverImage);
    final logo = webSafeImageUrl(store.logo);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(store.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: CustomScrollView(
          slivers: [
          if (store.openingHours?.isOpenNow(DateTime.now()) == false)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Material(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.schedule_rounded, color: Colors.red.shade800),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'مغلق الآن — يمكنك تصفح المنتجات، وقد تختلف أوقات الاستجابة.',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.tajawal(
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade900,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    GestureDetector(
                      onTap: () => openImageViewer(
                        context,
                        imageUrl: cover,
                        title: store.name,
                      ),
                      child: AmmarCachedImage(
                        imageUrl: cover,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      height: 200,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFFFF6B00),
                            Color(0xFFE65100),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.54),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    left: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CircleAvatar(
                          radius: 35,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.lightOrange,
                            backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
                            child: logo.isEmpty
                                ? Icon(Icons.storefront_rounded, size: 36, color: AppColors.primaryOrange)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                store.name,
                                style: GoogleFonts.tajawal(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  FutureBuilder<FeatureState<RatingAggregate>>(
                                    future: ReviewsRepository.instance.getAggregate(targetId: store.id, targetType: 'store'),
                                    builder: (context, snap) {
                                      if (snap.hasError) {
                                        return _StoreRatingBadge(
                                          rating: store.rating,
                                          totalReviews: store.reviewCount,
                                          onTap: _openReviewsDialog,
                                        );
                                      }
                                      final data = snap.data;
                                      final r = data is FeatureSuccess<RatingAggregate>
                                          ? data.data.averageRating
                                          : store.rating;
                                      final rc = data is FeatureSuccess<RatingAggregate>
                                          ? data.data.totalReviews
                                          : store.reviewCount;
                                      return _StoreRatingBadge(
                                        rating: r,
                                        totalReviews: rc,
                                        onTap: _openReviewsDialog,
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(Icons.access_time_rounded, color: Colors.white.withValues(alpha: 0.95), size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      store.deliveryTime.isNotEmpty ? store.deliveryTime : '—',
                                      style: GoogleFonts.tajawal(color: Colors.white, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Consumer<StoreController>(
                builder: (context, sc, _) {
                  return _TopDeliveryInfoCard(
                    policy: store.shippingPolicy,
                    store: store,
                    customerCity: sc.profile?.city,
                  );
                },
              ),
            ),
          ),
          if (kChatFeatureEnabled)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                    label: Text(
                      _isOwnStore() ? 'هذا متجرك — لا يمكن مراسلته من هنا' : 'تواصل مع المتجر',
                      style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isOwnStore() ? null : () => _openChat(context),
                  ),
                ),
              ),
            ),
          if (store.description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  store.description,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(height: 1.45, color: AppColors.textPrimary),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: FutureBuilder<({List<String> categoryNames, List<StoreShelfProduct> products})>(
              future: _catalogFuture,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'الخدمة غير متاحة مؤقتاً. حاول لاحقاً.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                    ),
                  );
                }
                if (!snap.hasData) return const SizedBox.shrink();
                final names = snap.data!.categoryNames;
                if (names.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 50,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: names.length,
                    itemBuilder: (ctx, i) {
                      final name = names[i];
                      final selected = _selectedCat == name;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCat = name);
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => StoreCategoryPage(store: store, categoryName: name),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFFF6B00) : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              name,
                              style: GoogleFonts.tajawal(
                                color: selected ? Colors.white : const Color(0xFFFF6B00),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _StoreProductsByCategorySection(
              store: store,
              catalogFuture: _catalogFuture,
              onRetryCatalog: () {
                setState(() {
                  _catalogFuture = _loadCatalog();
                });
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

/// أقسام المنتجات: عنوان + «عرض الكل» + تمرير أفقي (حتى 10).
class _StoreProductsByCategorySection extends StatelessWidget {
  const _StoreProductsByCategorySection({
    required this.store,
    required this.catalogFuture,
    required this.onRetryCatalog,
  });

  final StoreModel store;
  final Future<({List<String> categoryNames, List<StoreShelfProduct> products})> catalogFuture;
  final VoidCallback onRetryCatalog;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<String> categoryNames, List<StoreShelfProduct> products})>(
      future: catalogFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'تعذّر تحميل منتجات المتجر. تحقق من الاتصال ثم أعد المحاولة.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onRetryCatalog,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                    child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const StoreDetailCatalogShimmer();
        }
        final data = snap.data;
        if (data == null) {
          return const SizedBox.shrink();
        }
        final available = data.products;
        final catNames = data.categoryNames;

        if (catNames.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'لا يوجد منتجات',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final catName in catNames) _CategoryProductRow(store: store, categoryName: catName, products: available),
          ],
        );
      },
    );
  }
}

class _CategoryProductRow extends StatelessWidget {
  const _CategoryProductRow({
    required this.store,
    required this.categoryName,
    required this.products,
  });

  final StoreModel store;
  final String categoryName;
  final List<StoreShelfProduct> products;

  @override
  Widget build(BuildContext context) {
    final cat = categoryName.trim();
    final inCat = products.where((p) => p.shelfCategory.trim() == cat).take(10).toList();
    if (inCat.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  cat,
                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => StoreCategoryPage(store: store, categoryName: cat),
                    ),
                  );
                },
                child: Text('عرض الكل', style: GoogleFonts.tajawal(color: const Color(0xFFFF6B00), fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: inCat.length,
            itemBuilder: (context, i) {
              final p = inCat[i];
              return _HorizontalStoreProductTile(store: store, product: p);
            },
          ),
        ),
      ],
    );
  }
}

class _HorizontalStoreProductTile extends StatelessWidget {
  const _HorizontalStoreProductTile({required this.store, required this.product});

  final StoreModel store;
  final StoreShelfProduct product;

  @override
  Widget build(BuildContext context) {
    final storeController = context.read<StoreController>();
    final img = webSafeFirstProductImage(product.imageUrls);

    return GestureDetector(
      onTap: () {
        openProductPage(context, product: product.toCartProduct());
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(left: 12, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: img.isNotEmpty
                  ? AmmarCachedImage(
                      imageUrl: img,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      productTileStyle: true,
                    )
                  : Container(
                      height: 120,
                      color: Colors.grey.shade200,
                      child: Icon(Icons.inventory_2_outlined, color: Colors.grey.shade500),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${product.priceDisplay} دينار',
                    style: GoogleFonts.tajawal(
                      color: const Color(0xFFFF6B00),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 28,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        await storeController.addToCart(
                          product.toCartProduct(),
                          storeId: store.id,
                          storeName: store.name,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('تمت الإضافة ✓', style: GoogleFonts.tajawal()),
                              backgroundColor: Colors.green.shade700,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Text('أضف للسلة', style: GoogleFonts.tajawal(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreRatingBadge extends StatelessWidget {
  const _StoreRatingBadge({
    required this.rating,
    required this.totalReviews,
    required this.onTap,
  });

  final double rating;
  final int totalReviews;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.shade100.withValues(alpha: 0.95),
              Colors.deepOrange.shade200.withValues(alpha: 0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              rating.toStringAsFixed(1),
              style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 4),
            Text(
              '($totalReviews تقييم)',
              style: GoogleFonts.tajawal(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopDeliveryInfoCard extends StatelessWidget {
  const _TopDeliveryInfoCard({
    required this.policy,
    required this.store,
    this.customerCity,
  });

  final ShippingPolicy policy;
  final StoreModel store;
  final String? customerCity;

  @override
  Widget build(BuildContext context) {
    final noService = !store.hasOwnDrivers || policy.type == 'none';
    String feeText;
    if (noService) {
      feeText = 'لا يوجد توصيل';
    } else {
      switch (policy.type) {
        case 'free':
          feeText = 'مجاني';
          break;
        case 'percentage':
          feeText = '${policy.amount ?? 0}%';
          break;
        case 'perItem':
          feeText = '${(policy.amount ?? 0).toStringAsFixed(2)} د.أ/منتج';
          break;
        case 'fixed':
        default:
          feeText = '${(policy.amount ?? 2.0).toStringAsFixed(2)} د.أ';
          break;
      }
    }
    final etaText = policy.estimatedDays != null && policy.estimatedDays! > 0
        ? '${policy.estimatedDays} يوم'
        : '—';
    var areaText = '—';
    if (!noService) {
      if (store.deliveryAreas.isEmpty || store.deliveryAreas.contains('كل الأردن')) {
        areaText = 'جميع المحافظات';
      } else {
        areaText = store.deliveryAreas.join('، ');
      }
      if (policy.freeShippingThreshold != null && policy.freeShippingThreshold! > 0) {
        areaText = '$areaText · مجاني فوق ${policy.freeShippingThreshold} د.أ';
      }
    }
    final city = customerCity?.trim() ?? '';
    final blocked = !noService &&
        city.isNotEmpty &&
        !store.deliversToCustomerCity(customerCity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade50, Colors.orange.shade100],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.shade200.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(child: _deliveryInfoItem(Icons.local_shipping_rounded, 'رسوم التوصيل', feeText)),
              const SizedBox(width: 10),
              Expanded(child: _deliveryInfoItem(Icons.timer_rounded, 'مدة التوصيل', etaText)),
              const SizedBox(width: 10),
              Expanded(child: _deliveryInfoItem(Icons.location_on_rounded, 'مناطق التوصيل', areaText)),
            ],
          ),
        ),
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'لا يوجد توصيل لمنطقتك',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

Widget _deliveryInfoItem(IconData icon, String title, String value) {
  return Column(
    children: [
      Icon(icon, color: const Color(0xFFFF6B00), size: 22),
      const SizedBox(height: 6),
      Text(
        title,
        textAlign: TextAlign.center,
        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textPrimary),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary, height: 1.25),
      ),
    ],
  );
}



