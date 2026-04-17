import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/contracts/feature_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/feature_state_builder.dart';
import '../../../core/utils/web_image_url.dart';
import '../../../core/widgets/ammar_cached_image.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/seo/seo_routes.dart';
import '../../../core/seo/seo_service.dart';
import '../../store/presentation/store_controller.dart';
import '../data/stores_repository.dart';
import '../domain/store_model.dart';
import '../domain/store_shelf_product.dart';

/// كل منتجات قسم واحد داخل متجر (`shelfCategory` يطابق [categoryName]).
class StoreCategoryPage extends StatelessWidget {
  const StoreCategoryPage({
    super.key,
    required this.store,
    required this.categoryName,
  });

  final StoreModel store;
  final String categoryName;

  @override
  Widget build(BuildContext context) {
    final cat = categoryName.trim();
    SeoService.apply(
      SeoData(
        title: '$cat | AmmarJo',
        description: 'Browse $cat products on AmmarJo marketplace.',
        keywords: 'AmmarJo, category, $cat',
        path: SeoRoutes.category(cat),
      ),
      updatePath: true,
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(
          cat.isEmpty ? store.name : cat,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
        ),
      ),
      body: FutureBuilder<FeatureState<List<StoreShelfProduct>>>(
        future: StoresRepository.instance.fetchStoreShelfProducts(store.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
          }
          if (!snap.hasData) {
            return const SizedBox.shrink();
          }
          return buildFeatureStateUi<List<StoreShelfProduct>>(
            context: context,
            state: snap.data!,
            dataBuilder: (ctx, all) {
              final products = all
                  .where((p) => p.isAvailable && p.shelfCategory.trim() == cat)
                  .toList();
              if (products.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'لا منتجات في هذا القسم.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: products.length,
                itemBuilder: (context, i) {
                  final p = products[i];
                  final img = webSafeFirstProductImage(p.imageUrls);
                  return _CategoryProductCard(store: store, product: p, imageUrl: img);
                },
              );
            },
          );
        },
      ),
    );
  }
}


class _CategoryProductCard extends StatelessWidget {
  const _CategoryProductCard({
    required this.store,
    required this.product,
    required this.imageUrl,
  });

  final StoreModel store;
  final StoreShelfProduct product;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final storeController = context.read<StoreController>();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: imageUrl.isEmpty
                  ? ColoredBox(
                      color: AppColors.lightOrange,
                      child: Icon(Icons.image_outlined, color: AppColors.primaryOrange.withValues(alpha: 0.5)),
                    )
                  : AmmarCachedImage(imageUrl: imageUrl, fit: BoxFit.cover, productTileStyle: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.priceDisplay} JD',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(color: AppColors.darkOrange, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(double.infinity, 36),
                  ),
                  onPressed: () async {
                    final cartProduct = product.toCartProduct();
                    await storeController.addToCart(
                      cartProduct,
                      storeId: store.id,
                      storeName: store.name,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('أُضيف إلى السلة', style: GoogleFonts.tajawal())),
                      );
                    }
                  },
                  child: Text('أضف للسلة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                TextButton(
                  onPressed: () {
                    openProductPage(context, product: product.toCartProduct());
                  },
                  child: Text('التفاصيل', style: GoogleFonts.tajawal(color: AppColors.primaryOrange, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
