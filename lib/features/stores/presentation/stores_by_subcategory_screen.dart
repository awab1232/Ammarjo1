import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/contracts/feature_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/widgets/feature_state_builder.dart';
import '../data/stores_repository.dart';
import '../domain/store_model.dart';
import '../../store/presentation/pages/filtered_products_screen.dart';

class StoresBySubCategoryScreen extends StatelessWidget {
  const StoresBySubCategoryScreen({
    super.key,
    required this.subCategoryId,
    required this.subCategoryName,
  });

  final String subCategoryId;
  final String subCategoryName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(subCategoryName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: FutureBuilder<FeatureState<List<StoreModel>>>(
        future: StoresRepository.instance.getStoresBySubCategory(subCategoryId),
        initialData: const FeatureFailure<List<StoreModel>>('LOADING_STORES_BY_SUB_CATEGORY'),
        builder: (context, snapshot) {
          return buildFeatureStateUi<List<StoreModel>>(
            context: context,
            state: snapshot.requireData,
            dataBuilder: (ctx, stores) {
              return ListView.separated(
                itemCount: stores.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final store = stores[index];
                  return ListTile(
                    title: Text(store.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    subtitle: Text(store.category, style: GoogleFonts.tajawal()),
                    onTap: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => FilteredProductsScreen(
                            storeId: store.id,
                            subCategoryId: subCategoryId,
                            title: '${store.name} - $subCategoryName',
                          ),
                        ),
                      );
                    },
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
