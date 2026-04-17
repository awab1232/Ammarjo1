import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/seo/seo_routes.dart';
import '../../domain/models.dart';
import '../store_controller.dart';

/// بطاقة شبكة — منطقة صورة ١:١ مع [BoxFit.contain] (صور مُخزَّنة مؤقتاً) وخلفية رمادية فاتحة.
class StoreProductCard extends StatelessWidget {
  static const double imageAspectRatio = 1.0;

  final StoreController store;
  final Product product;

  const StoreProductCard({super.key, required this.store, required this.product});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebProductCard(context);
    }
    return _buildMobileProductCard(context);
  }

  Widget _buildMobileProductCard(BuildContext context) {
    final fav = store.isFavorite(product.id);
    final safeUrl = webSafeFirstProductImage(product.images);

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      shadowColor: AppColors.shadow,
      child: InkWell(
        onTap: () => openProductPage(context, product: product),
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: AspectRatio(
                    aspectRatio: imageAspectRatio,
                    child: ColoredBox(
                      color: const Color(0xFFF0F1F4),
                      child: safeUrl.isEmpty
                          ? AmmarCachedImage.placeholder(context)
                          : Padding(
                              padding: const EdgeInsets.all(12),
                              child: AmmarCachedImage(
                                imageUrl: safeUrl,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                productTileStyle: true,
                              ),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async {
                        await store.toggleFavorite(product.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 20, color: fav ? AppColors.orange : AppColors.textSecondary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.25),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                store.formatPrice(product.price),
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                height: 38,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    store.addToCart(product);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الإضافة إلى السلة'), behavior: SnackBarBehavior.floating));
                  },
                  child: const Text('أضف للسلة', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebProductCard(BuildContext context) {
    final fav = store.isFavorite(product.id);
    final safeUrl = webSafeFirstProductImage(product.images);

    return Card(
      elevation: 2,
      color: Colors.white,
      shadowColor: AppColors.shadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProductPage(context, product: product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: ColoredBox(
                    color: const Color(0xFFF0F1F4),
                    child: safeUrl.isEmpty
                        ? AmmarCachedImage.placeholder(context)
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: AmmarCachedImage(
                              imageUrl: safeUrl,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              productTileStyle: true,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () async => store.toggleFavorite(product.id),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 20,
                          color: fav ? AppColors.orange : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      store.formatPrice(product.price),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 36,
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          store.addToCart(product);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تمت الإضافة إلى السلة'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_shopping_cart, size: 16),
                        label: const Text('أضف للسلة', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
