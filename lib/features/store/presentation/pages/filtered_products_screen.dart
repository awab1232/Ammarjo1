import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/product_filter_repository.dart';
import '../../../../core/models/marketplace_product.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/feature_state_builder.dart';

class FilteredProductsScreen extends StatelessWidget {
  const FilteredProductsScreen({
    super.key,
    this.storeId,
    this.subCategoryId,
    this.sectionId,
    this.title,
  });

  final String? storeId;
  final String? subCategoryId;
  final String? sectionId;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(title ?? 'المنتجات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: FutureBuilder<FeatureState<List<MarketplaceProduct>>>(
        future: ProductFilterRepository.instance.getFilteredProducts(
          storeId: storeId,
          subCategoryId: subCategoryId,
          sectionId: sectionId,
        ),
        initialData: const FeatureFailure<List<MarketplaceProduct>>('LOADING_FILTERED_PRODUCTS'),
        builder: (context, snapshot) {
          return buildFeatureStateUi<List<MarketplaceProduct>>(
            context: context,
            state: snapshot.requireData,
            dataBuilder: (context, products) {
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: products.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemBuilder: (context, index) {
                  final product = products[index];
                  final imageUrl = product.image == null ? '' : webSafeImageUrl(product.image!);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: imageUrl.isNotEmpty
                                ? AmmarCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
                                : const Icon(Icons.image_not_supported_outlined, size: 40, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.price.toStringAsFixed(2),
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, color: AppColors.primaryOrange),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
