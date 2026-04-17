import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../store/domain/models.dart';

/// صف نتيجة منتج في بحث صفحة المتاجر — نقرة للتفاصيل، و«زيارة المتجر» + «أضف للسلة».
class StoresSearchProductTile extends StatelessWidget {
  const StoresSearchProductTile({
    super.key,
    required this.product,
    required this.storeId,
    required this.storeName,
    required this.onProductTap,
    required this.onVisitStore,
    required this.onAddToCart,
  });

  final Product product;
  final String storeId;
  final String storeName;
  final VoidCallback onProductTap;
  final VoidCallback onVisitStore;
  final VoidCallback onAddToCart;

  static const Color _orange = Color(0xFFFF6B00);

  @override
  Widget build(BuildContext context) {
    final img = webSafeFirstProductImage(product.images);

    return Card(
      key: ValueKey<String>('${storeId}_${product.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: onProductTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: img.isEmpty
                        ? Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey[200],
                            child: Icon(Icons.inventory_2_outlined, color: Colors.grey[600]),
                          )
                        : AmmarCachedImage(
                            imageUrl: img,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            productTileStyle: true,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '🏪 $storeName',
                          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        Text(
                          '${product.price} دينار',
                          style: GoogleFonts.tajawal(
                            color: _orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onVisitStore,
                    child: Text('زيارة المتجر', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _orange,
                      side: const BorderSide(color: _orange),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: onAddToCart,
                    child: Text('أضف للسلة', style: GoogleFonts.tajawal(color: _orange, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
