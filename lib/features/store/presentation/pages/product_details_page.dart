import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/seo/seo_routes.dart';
import '../../../../core/seo/seo_service.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/full_screen_image_viewer.dart';
import '../../../../core/services/growth_analytics_service.dart';
import '../../../../core/services/growth_push_logic_service.dart';
import '../../../reviews/presentation/widgets/reviews_section.dart';
import '../../../promotions/data/promotion_repository.dart';
import '../../../promotions/domain/promotion_model.dart';
import '../../domain/models.dart';
import '../controllers/cart_controller.dart';
import '../controllers/catalog_controller.dart';
import '../store_controller.dart';
import 'smart_quantity_calculator_page.dart';

class ProductDetailsPage extends StatelessWidget {
  final Product product;

  /// عند الفتح من بحث المتاجر: ربط «أضف للسلة» بمتجر المنتج (`product.id` هو معرّف المنتج في الكتالوج).
  final String? cartStoreId;
  final String? cartStoreName;

  const ProductDetailsPage({
    super.key,
    required this.product,
    this.cartStoreId,
    this.cartStoreName,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.read<StoreController>();
    final catalog = context.watch<CatalogController>();
    final cart = context.read<CartController>();
    final safeImage = webSafeFirstProductImage(product.images);
    final fav = context.select<StoreController, bool>(
      (s) => s.isFavorite(product.id),
    );
    final related = _relatedProducts(catalog.products, product);
    final available = product.isAvailableForPurchase;
    final viewersNow = 8 + (product.id % 17);
    final isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 1000;
    SeoService.apply(
      SeoData(
        title: '${product.name} | AmmarJo',
        description:
            product.description.replaceAll(RegExp('<[^>]*>'), '').trim().isEmpty
            ? product.displayDescription
            : product.description.replaceAll(RegExp('<[^>]*>'), '').trim(),
        keywords: 'AmmarJo, ${product.name}, construction products',
        path: SeoRoutes.product(product.id),
        imageUrl: safeImage,
        structuredData: <Map<String, dynamic>>[
          <String, dynamic>{
            '@context': 'https://schema.org',
            '@type': 'Product',
            'name': product.name,
            'description': product.displayDescription,
            'image': safeImage.isEmpty ? null : safeImage,
            'sku': '${product.id}',
            'offers': <String, dynamic>{
              '@type': 'Offer',
              'priceCurrency': 'JOD',
              'price': product.price,
              'availability': product.isAvailableForPurchase
                  ? 'https://schema.org/InStock'
                  : 'https://schema.org/OutOfStock',
              'url': SeoRoutes.product(product.id),
            },
          },
        ],
        internalLinks: related
            .take(8)
            .map((p) => SeoRoutes.product(p.id))
            .toList(),
      ),
      updatePath: true,
    );
    GrowthAnalyticsService.instance.logEvent(
      'view_product',
      payload: <String, Object?>{
        'product_id': product.id,
        'price': product.price,
      },
      dedupKey: 'product_${product.id}',
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: const AppBarBackButton(),
        title: Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.tajawal(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: fav ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
            onPressed: () async {
              await store.toggleFavorite(product.id);
            },
            icon: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: fav ? AppColors.orange : AppColors.textSecondary,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: available
                    ? AppColors.orange
                    : AppColors.textSecondary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: available
                  ? () async {
                      ProductVariant? selectedVariant;
                      if (product.hasVariants) {
                        selectedVariant = await _pickVariantForCart(context, product);
                        if (selectedVariant == null) return;
                      }
                      await cart.addToCart(
                        product,
                        storeId: cartStoreId ?? 'ammarjo',
                        storeName: cartStoreName ?? 'متجر عمار جو',
                        selectedVariant: selectedVariant,
                      );
                      if (!context.mounted) return;
                      if (cart.errorMessage != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              cart.errorMessage!,
                              style: GoogleFonts.tajawal(),
                            ),
                          ),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'تمت الإضافة إلى السلة',
                            style: GoogleFonts.tajawal(),
                          ),
                          action: SnackBarAction(
                            label: 'اقتراحات',
                            onPressed: () {},
                          ),
                        ),
                      );
                      GrowthAnalyticsService.instance.logEvent(
                        'add_to_cart',
                        payload: <String, Object?>{
                          'product_id': product.id,
                          'quantity': 1,
                        },
                      );
                      GrowthPushLogicService.instance.markCartActivity();
                    }
                  : null,
              child: Text(
                available ? 'أضف للسلة' : 'غير متوفر',
                style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
          if (isDesktopWeb)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: AppColors.surfaceSecondary,
                        child: safeImage.isEmpty
                            ? Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.orange.withValues(alpha: 0.5),
                              )
                            : GestureDetector(
                                onTap: () => openImageViewer(
                                  context,
                                  imageUrl: safeImage,
                                  title: product.name,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: AmmarCachedImage(
                                    imageUrl: safeImage,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    height: double.infinity,
                                    productTileStyle: true,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _ProductTopInfo(
                    product: product,
                    store: store,
                    available: available,
                  ),
                ),
              ],
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1,
                child: ColoredBox(
                  color: AppColors.surfaceSecondary,
                  child: safeImage.isEmpty
                      ? Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.orange.withValues(alpha: 0.5),
                        )
                      : GestureDetector(
                          onTap: () => openImageViewer(
                            context,
                            imageUrl: safeImage,
                            title: product.name,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: AmmarCachedImage(
                              imageUrl: safeImage,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              productTileStyle: true,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ProductTopInfo(
              product: product,
              store: store,
              available: available,
            ),
          ],
          if (productIsPaintContext(product, store)) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SmartQuantityCalculatorPage(anchorProduct: product),
                  ),
                );
              },
              icon: const Icon(Icons.calculate_outlined, size: 22),
              label: Text(
                'احسب كميتي',
                style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (product.stock > 0 && product.stock <= 5)
                _TrustChip(
                  icon: Icons.local_fire_department_rounded,
                  label: 'باقي ${product.stock} قطع',
                  color: Colors.red.shade700,
                ),
              _TrustChip(
                icon: Icons.remove_red_eye_outlined,
                label: '$viewersNow شخص يشاهد الآن',
                color: AppColors.orange,
              ),
              _TrustChip(
                icon: Icons.verified_rounded,
                label: 'متجر موثّق',
                color: const Color(0xFF2E7D32),
              ),
              if (product.isBoosted)
                _TrustChip(
                  icon: Icons.bolt_rounded,
                  label: 'منتج معزز',
                  color: Colors.purple,
                ),
              if (product.isTrending)
                _TrustChip(
                  icon: Icons.trending_up_rounded,
                  label: 'رائج الآن',
                  color: Colors.blue,
                ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<FeatureState<List<Promotion>>>(
            future: PromotionRepository.instance.getPromotionsForProduct(
              product.id,
              cartStoreId ?? 'ammarjo',
              categoryIds: product.categoryIds,
            ),
            builder: (context, snap) {
              final offers = switch (snap.data) {
                FeatureSuccess(:final data) => data,
                _ => const <Promotion>[],
              };
              if (offers.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: offers
                    .map(
                      (p) => Chip(
                        avatar: const Icon(
                          Icons.local_offer_outlined,
                          size: 18,
                        ),
                        label: Text(
                          '🔥 عرض اليوم • ${p.name}',
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            product.description.trim().isEmpty
                ? product.displayDescription
                : product.description.replaceAll(RegExp('<[^>]*>'), ''),
            style: GoogleFonts.tajawal(
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
          if (related.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'منتجات قد تحتاجها',
              style: GoogleFonts.tajawal(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: related.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: index == 0 ? 0 : 10,
                    ),
                    child: _RelatedProductCard(
                      product: related[index],
                      store: store,
                    ),
                  );
                },
              ),
            ),
          ],
          ReviewsSection(
            targetId: product.id.toString(),
            targetType: 'product',
            title: 'تقييمات المنتج',
            productWooIdForPurchaseCheck: product.id,
          ),
          ],
        ),
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.tajawal(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTopInfo extends StatelessWidget {
  const _ProductTopInfo({
    required this.product,
    required this.store,
    required this.available,
  });

  final Product product;
  final StoreController store;
  final bool available;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product.name,
          style: GoogleFonts.tajawal(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          store.formatPrice(_displayPrice(product)),
          style: GoogleFonts.tajawal(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.orange,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          available ? 'متوفر' : 'غير متوفر',
          style: GoogleFonts.tajawal(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: available
                ? const Color(0xFF2E7D32)
                : AppColors.textSecondary,
          ),
        ),
        Text(
          'العملة: ${store.currency.code}',
          style: GoogleFonts.tajawal(
            fontSize: 12,
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

String _displayPrice(Product product) {
  if (!product.hasVariants || product.variants.isEmpty) {
    return product.price;
  }
  final defaults = product.variants.where((v) => v.isDefault).toList();
  if (defaults.isNotEmpty) return defaults.first.price;
  final sorted = [...product.variants]
    ..sort((a, b) => (double.tryParse(a.price) ?? 0).compareTo(double.tryParse(b.price) ?? 0));
  return sorted.first.price;
}

Future<ProductVariant?> _pickVariantForCart(BuildContext context, Product product) async {
  final variants = product.variants;
  if (variants.isEmpty) return null;
  final defaultVariant = variants.firstWhere(
    (v) => v.isDefault,
    orElse: () => variants.first,
  );
  return showModalBottomSheet<ProductVariant>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('اختر متغير المنتج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
            ...variants.map((variant) {
              final opts = variant.options.map((o) => '${o.optionType}: ${o.optionValue}').join(' - ');
              return ListTile(
                title: Text(opts.isEmpty ? variant.id : opts, style: GoogleFonts.tajawal()),
                subtitle: Text(
                  'السعر: ${variant.price} - المخزون: ${variant.stock}',
                  style: GoogleFonts.tajawal(fontSize: 12),
                ),
                trailing: variant.id == defaultVariant.id ? const Icon(Icons.check_circle_outline) : null,
                onTap: () => Navigator.of(ctx).pop<ProductVariant>(variant),
              );
            }),
          ],
        ),
      );
    },
  );
}

/// Prefer same-category products, then others; exclude [current].
List<Product> _relatedProducts(List<Product> catalog, Product current) {
  final others = catalog.where((p) => p.id != current.id).toList();
  if (others.isEmpty) return <Product>[];
  if (current.categoryIds.isEmpty) {
    return others.take(12).toList();
  }
  final same = <Product>[];
  final diff = <Product>[];
  for (final p in others) {
    final overlap = p.categoryIds.any((c) => current.categoryIds.contains(c));
    if (overlap) {
      same.add(p);
    } else {
      diff.add(p);
    }
  }
  return [...same, ...diff].take(15).toList();
}

class _RelatedProductCard extends StatelessWidget {
  const _RelatedProductCard({required this.product, required this.store});

  final Product product;
  final StoreController store;

  @override
  Widget build(BuildContext context) {
    final img = webSafeFirstProductImage(product.images);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          openProductPage(context, product: product);
        },
        child: Ink(
          width: 152,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: img.isEmpty
                      ? ColoredBox(
                          color: AppColors.orangeLight,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.orange.withValues(alpha: 0.45),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(8),
                          child: AmmarCachedImage(
                            imageUrl: img,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            productTileStyle: true,
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tajawal(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  store.formatPrice(product.price),
                  style: GoogleFonts.tajawal(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orange,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
