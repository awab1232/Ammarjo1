import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../domain/models.dart';
import '../store_controller.dart';
import 'product_details_page.dart';

/// صفحة عرض قائمة منتجات كاملة (بعد «عرض المزيد»).
class ProductsHorizontalSectionPage extends StatelessWidget {
  const ProductsHorizontalSectionPage({
    super.key,
    required this.title,
    required this.products,
  });

  final String title;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const AppBarBackButton(),
        title: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
      ),
      body: products.isEmpty
          ? Center(child: Text('لا توجد منتجات', style: GoogleFonts.tajawal(color: AppColors.textSecondary)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.72,
              ),
              itemCount: products.length,
              itemBuilder: (context, i) {
                final p = products[i];
                final img = webSafeFirstProductImage(p.images);
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 1,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(product: p)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                            child: img.isEmpty
                                ? ColoredBox(color: AppColors.orangeLight, child: Icon(Icons.image_not_supported_outlined, color: AppColors.orange.withValues(alpha: 0.4)))
                                : Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: AmmarCachedImage(
                                      imageUrl: img,
                                      fit: BoxFit.contain,
                                      width: double.infinity,
                                      height: double.infinity,
                                      key: ValueKey<String>(img),
                                      productTileStyle: true,
                                    ),
                                  ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                          child: Text(
                            store.formatPrice(p.price),
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: AppColors.orange, fontSize: 14),
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
}
