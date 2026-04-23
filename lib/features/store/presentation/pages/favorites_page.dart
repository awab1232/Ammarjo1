import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/firebase/users_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../domain/favorite_product.dart';
import '../store_controller.dart';
import 'product_details_page.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Firebase.apps.isNotEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: const AppBarBackButton(),
          title: Text('المفضلة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
        ),
        body: Center(child: Text('يتطلب Firebase', style: GoogleFonts.tajawal())),
      );
    }

    final uid = UserSession.currentUid;
    if (!UserSession.isLoggedIn || uid.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: const AppBarBackButton(),
          title: Text('المفضلة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'سجّل الدخول لمزامنة المفضلة بين أجهزتك.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: const AppBarBackButton(),
        title: Text('المفضلة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<FeatureState<List<FavoriteProduct>>>(
        stream: UsersRepository.watchFavorites(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'تعذر تحميل المفضلة: ${snap.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: Colors.red),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.orange));
          }
          final list = switch (snap.data) {
            FeatureSuccess(:final data) => data,
            _ => <FavoriteProduct>[],
          };
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('لا توجد منتجات في المفضلة', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.52,
            ),
            itemBuilder: (context, i) => _FavCard(favorite: list[i]),
          );
        },
      ),
    );
  }
}

class _FavCard extends StatelessWidget {
  final FavoriteProduct favorite;

  const _FavCard({required this.favorite});

  @override
  Widget build(BuildContext context) {
    final store = context.read<StoreController>();
    final image = favorite.productImage.trim().isNotEmpty
        ? webSafeImageUrl(favorite.productImage)
        : '';
    final id = int.tryParse(favorite.productId) ?? 0;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: AppColors.shadow,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ProductDetailsPage(product: favorite.toMinimalProduct()),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 120,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: ColoredBox(
                  color: AppColors.surfaceSecondary,
                  child: image.isEmpty
                      ? Icon(Icons.image_not_supported_outlined, color: AppColors.orange.withValues(alpha: 0.5))
                      : Padding(
                          padding: const EdgeInsets.all(8),
                          child: AmmarCachedImage(
                            imageUrl: image,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            productTileStyle: true,
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                favorite.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                store.formatMoney(favorite.productPrice),
                style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          store.addToCart(favorite.toMinimalProduct());
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تمت الإضافة إلى السلة', style: GoogleFonts.tajawal())),
                          );
                        },
                        child: Text('أضف للسلة', style: GoogleFonts.tajawal(fontSize: 12)),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'حذف من المفضلة',
                    onPressed: id <= 0
                        ? null
                        : () async {
                            await store.removeFavorite(id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('تمت الإزالة من المفضلة', style: GoogleFonts.tajawal())),
                              );
                            }
                          },
                    icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
