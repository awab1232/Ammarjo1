import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/backend_orders_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/store_product_discount.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../store/domain/models.dart';
import '../../../store/presentation/pages/product_details_page.dart';
import '../../../store/presentation/store_controller.dart';
import '../../domain/store_model.dart';
import '../../domain/store_shelf_product.dart';

/// بطاقة متجر بعرض كامل مع معاينة منتجات أفقية (من `stores/{id}/products` ثم احتياطياً `products` حيث `storeId`).
class StoreExpandedCard extends StatelessWidget {
  const StoreExpandedCard({
    super.key,
    required this.store,
    required this.onVisitStore,
  });

  final StoreModel store;
  final VoidCallback onVisitStore;

  @override
  Widget build(BuildContext context) {
    final logoUrl = webSafeImageUrl(store.logo);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: ClipOval(
              child: logoUrl.isEmpty
                  ? CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.lightOrange,
                      child: Icon(Icons.storefront_rounded, color: AppColors.primaryOrange, size: 28),
                    )
                  : AmmarCachedImage(
                      imageUrl: logoUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
            ),
            title: Text(
              store.name,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              store.description.isEmpty ? '—' : store.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                Text(
                  store.rating.toStringAsFixed(1),
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
          ),
          if (store.category.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF6B00).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    store.category,
                    style: GoogleFonts.tajawal(
                      color: const Color(0xFFFF6B00),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          _StoreProductsPreviewStrip(store: store),
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                minimumSize: const Size(double.infinity, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onVisitStore,
              child: Text('زيارة المتجر', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreProductsPreviewStrip extends StatelessWidget {
  const _StoreProductsPreviewStrip({required this.store});

  final StoreModel store;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: BackendOrdersClient.instance
          .fetchProductsByStore(storeId: store.id, limit: 10)
          .then((v) => v ?? const <Map<String, dynamic>>[]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'لا معاينة منتجات',
                style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return _horizontalProductsPreview(context, rows);
      },
    );
  }

  static const int _previewCount = 4;

  Widget _horizontalProductsPreview(
    BuildContext context,
    List<Map<String, dynamic>> rows,
  ) {
    final preview = rows.take(_previewCount).toList();
    return SizedBox(
      height: 280,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        itemCount: preview.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = preview[i];
          final imgUrl = webSafeFirstProductImage(p['image_urls'] ?? p['imageUrls'] ?? p['images'] ?? p['imageUrl']);
          final name = p['name']?.toString() ?? '';
          final pricing = StoreProductDiscountView.fromProductMap(p);
          final price = pricing.basePrice;
          final hasDiscount = pricing.hasActiveDiscount;
          final priceLabel = pricing.effectivePrice.toStringAsFixed(2);
          final baseCartProduct = StoreShelfProduct.fromBackendRow(store.id, p).toCartProduct();
          final cartProduct = Product(
            id: baseCartProduct.id,
            name: baseCartProduct.name,
            description: baseCartProduct.description,
            price: hasDiscount ? pricing.effectivePrice.toString() : baseCartProduct.price,
            images: baseCartProduct.images,
            categoryIds: baseCartProduct.categoryIds,
          );
          return SizedBox(
            width: 158,
            child: Material(
              color: AppColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ProductDetailsPage(
                        product: cartProduct,
                        cartStoreId: store.id,
                        cartStoreName: store.name,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: imgUrl.isEmpty
                            ? Container(
                                height: 120,
                                color: AppColors.surfaceSecondary,
                                alignment: Alignment.center,
                                child: Icon(Icons.image_outlined, color: AppColors.textSecondary, size: 32),
                              )
                            : AmmarCachedImage(
                                imageUrl: imgUrl,
                                height: 120,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                productTileStyle: true,
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$priceLabel د.أ',
                        style: GoogleFonts.tajawal(color: AppColors.primaryOrange, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      if (hasDiscount)
                        Text(
                          '${price.toStringAsFixed(2)} د.أ',
                          style: GoogleFonts.tajawal(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () async {
                          final sc = context.read<StoreController>();
                          await sc.addToCart(
                            cartProduct,
                            storeId: store.id,
                            storeName: store.name,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('تمت الإضافة للسلة', style: GoogleFonts.tajawal())),
                            );
                          }
                        },
                        child: Text('أضف للسلة', style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// بطاقة متجر عمار جو المثبتة — حدود برتقالية + شارة + معاينة من الكتالوج الرئيسي.
class PinnedAmmarJoExpandedCard extends StatelessWidget {
  const PinnedAmmarJoExpandedCard({
    super.key,
    required this.catalogProducts,
    required this.onVisitCatalog,
  });

  final List<Product> catalogProducts;
  final VoidCallback onVisitCatalog;

  @override
  Widget build(BuildContext context) {
    final preview = catalogProducts.take(4).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.primaryOrange, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.primaryOrange,
              child: Text('عج', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    'متجر عمار جو',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '⭐ متجر مميز',
                    style: GoogleFonts.tajawal(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              'متجرنا الرسمي — مواد بناء وأدوات',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                Text(
                  '5.0',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
          ),
          if (preview.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'جاري تحميل المنتجات…',
                  style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SizedBox(
              height: 280,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                itemCount: preview.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final p = preview[i];
                  final imgUrl = webSafeFirstProductImage(p.images);
                  return SizedBox(
                    width: 158,
                    child: Material(
                      color: AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => ProductDetailsPage(
                                product: p,
                                cartStoreId: 'ammarjo',
                                cartStoreName: 'متجر عمار جو',
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imgUrl.isEmpty
                                    ? Container(
                                        height: 120,
                                        color: AppColors.surfaceSecondary,
                                        alignment: Alignment.center,
                                        child: Icon(Icons.image_outlined, color: AppColors.textSecondary, size: 32),
                                      )
                                    : AmmarCachedImage(
                                        imageUrl: imgUrl,
                                        height: 120,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        productTileStyle: true,
                                      ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${p.price} د.أ',
                                style: GoogleFonts.tajawal(
                                  color: AppColors.primaryOrange,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  final sc = context.read<StoreController>();
                                  await sc.addToCart(
                                    p,
                                    storeId: 'ammarjo',
                                    storeName: 'متجر عمار جو',
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('تمت الإضافة للسلة', style: GoogleFonts.tajawal())),
                                    );
                                  }
                                },
                                child: Text('أضف للسلة', style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w700)),
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
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryOrange,
                minimumSize: const Size(double.infinity, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onVisitCatalog,
              child: Text('زيارة المتجر', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
