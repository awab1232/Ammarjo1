import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/home_repository.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/models/sub_category.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/feature_state_builder.dart';
import '../../../maintenance/presentation/pages/maintenance_page.dart';
import '../../../stores/presentation/stores_by_subcategory_screen.dart';
import 'filtered_products_screen.dart';

class SubCategoryScreen extends StatelessWidget {
  const SubCategoryScreen({super.key, required this.section});

  final HomeSection section;

  FeatureState<WidgetBuilder> _resolveDestination(SubCategory item) {
    switch (section.type.trim().toLowerCase()) {
      case 'stores':
        return FeatureState.success(
          (_) => StoresBySubCategoryScreen(subCategoryId: item.id, subCategoryName: item.name),
        );
      case 'technicians':
        return FeatureState.success((_) => MaintenancePage(initialCategoryId: item.id));
      case 'services':
        return FeatureState.success(
          (_) => FilteredProductsScreen(
            subCategoryId: item.id,
            sectionId: section.id,
            title: item.name,
          ),
        );
      default:
        return FeatureState.failure('UNKNOWN_SECTION_TYPE');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(
          section.name,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<FeatureState<List<SubCategory>>>(
        future: HomeRepository.instance.getSubCategories(section.id),
        initialData: const FeatureFailure<List<SubCategory>>('LOADING_SUB_CATEGORIES'),
        builder: (context, snapshot) {
          return buildFeatureStateUi<List<SubCategory>>(
            context: context,
            state: snapshot.requireData,
            dataBuilder: (context, items) {
              final destinationState =
                  items.isEmpty ? FeatureState.success((_) => const SizedBox.shrink()) : _resolveDestination(items.first);
              if (destinationState is FeatureFailure<WidgetBuilder>) {
                return buildFeatureStateUi<WidgetBuilder>(
                  context: context,
                  state: destinationState,
                  dataBuilder: (_, builder) => builder(context),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final imageUrl = item.image == null ? '' : webSafeImageUrl(item.image!);
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      final state = _resolveDestination(item);
                      if (state is FeatureSuccess<WidgetBuilder>) {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: state.data),
                        );
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (imageUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: AmmarCachedImage(
                                imageUrl: imageUrl,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            const Icon(Icons.category_rounded, color: AppColors.primaryOrange, size: 42),
                          const SizedBox(height: 8),
                          Text(
                            item.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.tajawal(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.heading,
                            ),
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
