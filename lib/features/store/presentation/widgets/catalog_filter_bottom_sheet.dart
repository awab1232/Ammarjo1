import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/catalog_active_filters.dart';
import '../../domain/models.dart';
import '../../domain/store_search_matcher.dart';
import '../store_controller.dart';

/// تصفية متقدمة (سعر + تصنيف) — تستدعي [StoreController.applyFilters].
Future<void> showCatalogFilterBottomSheet(
  BuildContext context,
  StoreController store,
) async {
  final prices = store.products.map(storeProductPrimaryPrice).whereType<double>().toList();
  var minBound = 0.0;
  var maxBound = 1000.0;
  if (prices.isNotEmpty) {
    minBound = prices.reduce(math.min);
    maxBound = prices.reduce(math.max);
    if (maxBound - minBound < 0.02) {
      maxBound = minBound + 1.0;
    }
  }

  final active = store.activeFilters;
  var minV = active?.minPrice ?? minBound;
  var maxV = active?.maxPrice ?? maxBound;
  if (minV > maxV) {
    final t = minV;
    minV = maxV;
    maxV = t;
  }
  int? categoryId = active?.categoryWooId;

  final categories = store.categories.isNotEmpty
      ? store.categories
      : store.categoriesForHomePage;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.paddingOf(ctx).bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setModal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تصفية المنتجات',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'السعر (${store.currency.code})',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                ),
                RangeSlider(
                  values: RangeValues(minV, maxV),
                  min: minBound,
                  max: maxBound,
                  divisions: math.min(40, ((maxBound - minBound) * 4).round().clamp(4, 80)),
                  labels: RangeLabels(
                    minV.toStringAsFixed(2),
                    maxV.toStringAsFixed(2),
                  ),
                  activeColor: AppColors.orange,
                  onChanged: (r) {
                    setModal(() {
                      minV = r.start;
                      maxV = r.end;
                    });
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(minV.toStringAsFixed(2), style: GoogleFonts.tajawal(fontSize: 12)),
                    Text(maxV.toStringAsFixed(2), style: GoogleFonts.tajawal(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'التصنيف',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<int?>(
                  // ignore: deprecated_member_use — initialValue لا يحدّث الاختيار داخل StatefulBuilder
                  value: categoryId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  hint: Text('كل التصنيفات', style: GoogleFonts.tajawal()),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text('كل التصنيفات', style: GoogleFonts.tajawal()),
                    ),
                    ...categories.map(
                      (ProductCategory c) => DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text(c.name, style: GoogleFonts.tajawal(), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setModal(() => categoryId = v),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await store.clearFilters();
                          if (context.mounted) Navigator.pop(ctx);
                        },
                        child: Text('إعادة تعيين', style: GoogleFonts.tajawal()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                        onPressed: store.isApplyingFilters
                            ? null
                            : () async {
                                await store.applyFilters(
                                  CatalogActiveFilters(
                                    minPrice: minV,
                                    maxPrice: maxV,
                                    categoryWooId: categoryId,
                                  ),
                                );
                                if (context.mounted) Navigator.pop(ctx);
                              },
                        child: Text('تطبيق', style: GoogleFonts.tajawal(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
