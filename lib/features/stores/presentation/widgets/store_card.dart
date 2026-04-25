import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/utils/web_image_url.dart';
import '../../domain/store_model.dart';

class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, required this.onTap});

  final StoreModel store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logoUrl = webSafeImageUrl(store.logo);
    final coverUrl = webSafeImageUrl(store.coverImage);
    final cityLine = store.cities.isEmpty
        ? ''
        : store.cities.contains('all')
            ? 'الأردن كاملة'
            : store.cities.take(2).join('، ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (context, error, stackTrace) => Container(
                        height: 130,
                        color: const Color(0xFFF5F5F5),
                        child: const Icon(
                          Icons.storefront_rounded,
                          size: 50,
                          color: Color(0xFFE8471A),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 10,
                    left: 10,
                    child: _OpenBadge(),
                  ),
                  Positioned(
                    bottom: -20,
                    right: 16,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: logoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, error, stackTrace) => Container(
                            color: const Color(0xFFF5F5F5),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: Color(0xFFE8471A),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: GoogleFonts.tajawal(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      store.category,
                      style: GoogleFonts.tajawal(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ...List.generate(5, (i) {
                          final ic = i < store.rating.round().clamp(0, 5)
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded;
                          return Icon(ic, size: 16, color: const Color(0xFFFFB800));
                        }),
                        const SizedBox(width: 4),
                        Text(
                          '(${store.reviewCount})',
                          style: GoogleFonts.tajawal(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    if (cityLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        cityLine,
                        style: GoogleFonts.tajawal(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (store.freeDelivery) _badge('🚚 توصيل مجاني', const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
                        if (store.hasActivePromotions) _badge('🔥 عروض', const Color(0xFFC62828), const Color(0xFFFFEBEE)),
                        if (store.hasDiscountedProducts) _badge('💸 خصومات', const Color(0xFFC62828), const Color(0xFFFFEBEE)),
                        if (store.isBoosted) _badge('⭐ متجر مميز', const Color(0xFFF9A825), const Color(0xFFFFF8E1)),
                      ],
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

class _OpenBadge extends StatelessWidget {
  const _OpenBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'مفتوح',
        style: GoogleFonts.tajawal(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
