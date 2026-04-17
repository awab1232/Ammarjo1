import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../domain/store_model.dart';

class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, required this.onTap});

  final StoreModel store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logoUrl = webSafeImageUrl(store.logo);
    final cityLine = store.cities.isEmpty
        ? ''
        : store.cities.contains('all')
            ? 'الأردن كاملة'
            : store.cities.take(2).join('، ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: logoUrl.isEmpty
                    ? CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.lightOrange,
                        child: Icon(Icons.storefront_rounded, color: AppColors.primaryOrange, size: 32),
                      )
                    : AmmarCachedImage(
                        imageUrl: logoUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      store.name,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        if (store.freeDelivery) _badge('🚚 توصيل مجاني', const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
                        if (store.hasActivePromotions) _badge('🔥 عروض', const Color(0xFFC62828), const Color(0xFFFFEBEE)),
                        if (store.hasDiscountedProducts) _badge('💸 خصومات', const Color(0xFFC62828), const Color(0xFFFFEBEE)),
                        if (store.isBoosted) _badge('⭐ متجر مميز', const Color(0xFFF9A825), const Color(0xFFFFF8E1)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          store.rating.toStringAsFixed(1),
                          style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 4),
                        ...List.generate(5, (i) {
                          final pos = i + 1;
                          final r = store.rating;
                          IconData ic;
                          if (r >= pos) {
                            ic = Icons.star_rounded;
                          } else if (r >= pos - 0.5) {
                            ic = Icons.star_half_rounded;
                          } else {
                            ic = Icons.star_outline_rounded;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(ic, size: 16, color: AppColors.accentOrange),
                          );
                        }),
                        if (store.reviewCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '(${store.reviewCount} تقييم)',
                              style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                      ],
                    ),
                    if (cityLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        cityLine,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                    if (store.category.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
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
                    ],
                    const SizedBox(height: 8),
                    Text(
                      store.description.isEmpty ? '—' : store.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(fontSize: 13, height: 1.35, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _badge(String label, Color textColor, Color bg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: textColor.withValues(alpha: 0.25)),
    ),
    child: Text(
      label,
      style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w700, color: textColor),
    ),
  );
}
