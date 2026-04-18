import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';

/// Shimmer highlight used across home loading placeholders.
Widget ammarShimmerWrap({required Widget child}) {
  return Shimmer.fromColors(
    baseColor: const Color(0xFFE6E8EC),
    highlightColor: const Color(0xFFF2F4F7),
    period: const Duration(milliseconds: 1200),
    child: child,
  );
}

/// Banner area skeleton (matches [_StoresHomePageBannerCarousel] height).
class HomeBannerSkeleton extends StatelessWidget {
  const HomeBannerSkeleton({
    super.key,
    this.height = 196,
    this.horizontalPadding = 16,
    this.verticalPadding = 8,
  });

  final double height;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding),
      child: ammarShimmerWrap(
        child: Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// Horizontal strip of card-shaped placeholders.
class HomeHorizontalCardsSkeleton extends StatelessWidget {
  const HomeHorizontalCardsSkeleton({
    super.key,
    this.height = 148,
    this.cardWidth = 158,
    this.count = 5,
    this.spacing = 12,
  });

  final double height;
  final double cardWidth;
  final int count;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ammarShimmerWrap(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          physics: const BouncingScrollPhysics(),
          itemCount: count,
          separatorBuilder: (context, _) => SizedBox(width: spacing),
          itemBuilder: (context, _) => Container(
            width: cardWidth,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact store chips row skeleton.
class HomeStoreChipsSkeleton extends StatelessWidget {
  const HomeStoreChipsSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ammarShimmerWrap(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          physics: const BouncingScrollPhysics(),
          itemCount: count,
          separatorBuilder: (context, _) => const SizedBox(width: 10),
          itemBuilder: (context, _) => Container(
            width: 118,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 10,
                  width: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical list of store row placeholders (stores grid section).
class HomeStoreListSkeleton extends StatelessWidget {
  const HomeStoreListSkeleton({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ammarShimmerWrap(
        child: Column(
          children: List<Widget>.generate(rows, (i) {
            return Padding(
              padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : 12),
              child: Container(
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 14,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 10,
                            width: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Offers row skeleton (taller cards).
class HomeOffersStripSkeleton extends StatelessWidget {
  const HomeOffersStripSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeHorizontalCardsSkeleton(height: 200, cardWidth: 168, count: 4, spacing: 12);
  }
}

/// Full-width bottom marketing banner placeholder.
class HomeBottomBannerSkeleton extends StatelessWidget {
  const HomeBottomBannerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ammarShimmerWrap(
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// شبكة منتجات (قسم متجر / شبكة مسطحة).
class ProductGridShimmer extends StatelessWidget {
  const ProductGridShimmer({
    super.key,
    this.crossAxisCount = 2,
    this.childAspectRatio = 0.72,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(12),
  });

  final int crossAxisCount;
  final double childAspectRatio;
  final int itemCount;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ammarShimmerWrap(
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, _) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          height: 12,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 10,
                          width: 56,
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// صفوف أفقية تشبه أقسام تفاصيل المتجر أثناء التحميل.
class StoreDetailCatalogShimmer extends StatelessWidget {
  const StoreDetailCatalogShimmer({super.key, this.sectionCount = 3});

  final int sectionCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List<Widget>.generate(sectionCount, (s) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: ammarShimmerWrap(
                    child: Row(
                      children: [
                        Container(
                          height: 18,
                          width: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: 14,
                          width: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 168,
                  child: ammarShimmerWrap(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      physics: const BouncingScrollPhysics(),
                      itemCount: 5,
                      separatorBuilder: (context, _) => const SizedBox(width: 10),
                      itemBuilder: (context, _) {
                        return Container(
                          width: 118,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border.withValues(alpha: 0.35)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// شريط رفيع أعلى المحتوى (مزامنة السلة).
class CartSyncShimmerBar extends StatelessWidget {
  const CartSyncShimmerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      width: double.infinity,
      child: ammarShimmerWrap(
        child: const ColoredBox(color: Colors.white),
      ),
    );
  }
}

/// بديل صغير لدوران الزر على خلفية برتقالية/داكنة.
class InlineLightButtonShimmer extends StatelessWidget {
  const InlineLightButtonShimmer({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.white38,
      highlightColor: Colors.white,
      period: const Duration(milliseconds: 900),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white38,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

/// لوحة حوار تحميل بدون دوار (مثلاً فتح محادثة).
class DialogLoadingPanel extends StatelessWidget {
  const DialogLoadingPanel({super.key, this.message = 'جاري التجهيز…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 6,
              width: 160,
              child: ammarShimmerWrap(
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(4))),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
