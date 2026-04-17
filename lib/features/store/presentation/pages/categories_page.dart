import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/utils/web_image_url.dart';
import '../store_controller.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StoreController>(
      builder: (context, store, child) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            leading: const AppBarBackButton(),
            title: const Text('الأقسام', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
          body: store.categoriesForHomePage.isEmpty
              ? const Center(child: Text('لا توجد أقسام', style: TextStyle(color: AppColors.textSecondary)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: store.categoriesForHomePage.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = store.categoriesForHomePage[i];
                    return Material(
                      elevation: 1,
                      shadowColor: AppColors.shadow,
                      borderRadius: BorderRadius.circular(16),
                      color: AppColors.background,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.orangeLight,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: item.imageUrl.isEmpty
                              ? Icon(Icons.category_rounded, color: AppColors.orange)
                              : Image.network(webSafeImageUrl(item.imageUrl), fit: BoxFit.cover),
                        ),
                        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
