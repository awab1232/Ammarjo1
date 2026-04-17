import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/seo/seo_routes.dart';
import '../../domain/models.dart';
import '../store_controller.dart';

/// بطاقة منتج — منطقة صورة بنسبة ثابتة (١:١)، [BoxFit.contain]، خلفية رمادية فاتحة، سعر وسلة في الأسفل.
class CompactProductCard extends StatelessWidget {
  /// نسبة عرض إلى ارتفاع منطقة الصورة (١:١ أو ٤:٣).
  static const double imageAspectRatio = 1.0;

  static const double defaultWidth = 148;

  final StoreController store;
  final Product product;
  final double width;

  const CompactProductCard({
    super.key,
    required this.store,
    required this.product,
    this.width = defaultWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebCompactCard(context);
    }
    return _buildMobileCompactCard(context);
  }

  Widget _buildMobileCompactCard(BuildContext context) {
    final safeUrl = webSafeFirstProductImage(product.images);

    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.background,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        child: InkWell(
          onTap: () => openProductPage(context, product: product),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: imageAspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: const Color(0xFFF0F1F4),
                      child: safeUrl.isEmpty
                          ? AmmarCachedImage.placeholder(context)
                          : Padding(
                              padding: const EdgeInsets.all(10),
                              child: AmmarCachedImage(
                                imageUrl: safeUrl,
                                key: ValueKey<String>(safeUrl),
                                fit: BoxFit.contain,
                                width: double.infinity,
                                height: double.infinity,
                                productTileStyle: true,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: AppColors.heading,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 28,
                  child: Text(
                    product.displayDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.2,
                      color: AppColors.textSecondary.withValues(alpha: 0.95),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Text(
                        store.formatPrice(product.price),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                          letterSpacing: 0.2,
                          height: 1.1,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        await store.addToCart(product);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تمت الإضافة إلى السلة'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.add_shopping_cart_outlined,
                          size: 22,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebCompactCard(BuildContext context) {
    final safeUrl = webSafeFirstProductImage(product.images);

    return SizedBox(
      width: width,
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shadowColor: AppColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openProductPage(context, product: product),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 170,
                child: ColoredBox(
                  color: const Color(0xFFF0F1F4),
                  child: safeUrl.isEmpty
                      ? AmmarCachedImage.placeholder(context)
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: AmmarCachedImage(
                            imageUrl: safeUrl,
                            key: ValueKey<String>(safeUrl),
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            productTileStyle: true,
                          ),
                        ),
                ),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: AppColors.heading,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        store.formatPrice(product.price),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 36,
                        child: FilledButton.icon(
                          onPressed: () async {
                            await store.addToCart(product);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تمت الإضافة إلى السلة'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_shopping_cart_outlined, size: 16),
                          label: const Text('أضف'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      ),
                    ],
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
