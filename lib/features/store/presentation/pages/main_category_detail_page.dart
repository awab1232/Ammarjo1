import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/main_category_hierarchy.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../domain/category_sub_image_lookup.dart';
import '../store_controller.dart';
import '../widgets/compact_product_card.dart';
import '../widgets/store_category_avatar.dart';
import 'category_flat_grid_page.dart';

/// ارتفاع صف المنتجات الأفقي — يتسع لبطاقة [CompactProductCard] بنسبة صورة ١:١.
const double _kProductRowHeight = 300;

/// صفحة قسم رئيسي: بانر، أقسام فرعية بصور من Firestore، تصفية فورية، ثلاثة أقسام أو قسم واحد عند التصفية.
class MainCategoryDetailPage extends StatefulWidget {
  const MainCategoryDetailPage({super.key, required this.main});

  final MainCategoryDefinition main;

  @override
  State<MainCategoryDetailPage> createState() => _MainCategoryDetailPageState();
}

class _MainCategoryDetailPageState extends State<MainCategoryDetailPage> {
  /// `null` = عرض الأقسام الثلاثة الافتراضية؛ غير ذلك = تصفية حسب فرع واحد.
  MainSubCategoryDefinition? _selectedSub;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    final main = widget.main;
    final subs = main.allSubCategories;
    final sections = main.sectionSubcategories;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 168,
            pinned: true,
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            leading: const AppBarBackButton(),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                main.titleAr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.orange.withValues(alpha: 0.95),
                      AppColors.navy.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 56,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'التصنيفات الفرعية',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 118,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: subs.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          final allSelected = _selectedSub == null;
                          return _SubCategoryVisualChip(
                            label: 'الكل',
                            imageUrl: null,
                            selected: allSelected,
                            onTap: () => setState(() => _selectedSub = null),
                          );
                        }
                        final sub = subs[i - 1];
                        final url = resolveSubCategoryImageUrl(
                          categories: store.categoriesForHomePage,
                          main: main,
                          sub: sub,
                        );
                        final selected = _selectedSub == sub;
                        return _SubCategoryVisualChip(
                          label: sub.titleAr,
                          imageUrl: url,
                          selected: selected,
                          onTap: () => setState(() => _selectedSub = sub),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_selectedSub == null) ...[
            for (var si = 0; si < 3; si++)
              SliverToBoxAdapter(
                child: _SubSectionBlock(
                  store: store,
                  main: main,
                  sub: sections[si],
                  sectionIndex: si,
                ),
              ),
          ] else
            SliverToBoxAdapter(
              child: _FilteredSubSectionBlock(
                store: store,
                main: main,
                sub: _selectedSub!,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _SubCategoryVisualChip extends StatelessWidget {
  const _SubCategoryVisualChip({
    required this.label,
    required this.imageUrl,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? imageUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 78,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? AppColors.orange : Colors.transparent,
                    width: 2.5,
                  ),
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: AppColors.orange.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: label == 'الكل'
                      ? Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Icon(
                            Icons.apps_rounded,
                            size: 30,
                            color: selected ? AppColors.orange : AppColors.textSecondary,
                          ),
                        )
                      : StoreCategoryAvatar(
                          imageUrl: imageUrl,
                          size: 64,
                          borderRadius: 12,
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  color: selected ? AppColors.orange : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewMoreTile extends StatelessWidget {
  const _ViewMoreTile({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 112,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.grid_view_rounded, size: 28, color: enabled ? AppColors.orange : AppColors.textSecondary),
                  const SizedBox(height: 10),
                  Text(
                    'عرض المزيد',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.w800, color: enabled ? AppColors.orange : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilteredSubSectionBlock extends StatelessWidget {
  const _FilteredSubSectionBlock({
    required this.store,
    required this.main,
    required this.sub,
  });

  final StoreController store;
  final MainCategoryDefinition main;
  final MainSubCategoryDefinition sub;

  @override
  Widget build(BuildContext context) {
    final sectionIndex = main.subCategories.indexOf(sub);
    final idx = sectionIndex < 0 ? 0 : sectionIndex;
    final row = productsForSubSection(store.products, main, sub, idx);
    final allForMore = allProductsForSub(store.products, main, sub, idx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Text(
            sub.titleAr,
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ),
        if (row.isEmpty && allForMore.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'لا توجد منتجات في هذا القسم حالياً',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 14),
            ),
          )
        else
          SizedBox(
            height: _kProductRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: row.length + (allForMore.isEmpty ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                if (i < row.length) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: CompactProductCard(store: store, product: row[i]),
                  );
                }
                return _ViewMoreTile(
                  enabled: allForMore.isNotEmpty,
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryFlatGridPage(
                          categoryName: '${main.titleAr} — ${sub.titleAr}',
                          presetProducts: allForMore,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SubSectionBlock extends StatelessWidget {
  const _SubSectionBlock({
    required this.store,
    required this.main,
    required this.sub,
    required this.sectionIndex,
  });

  final StoreController store;
  final MainCategoryDefinition main;
  final MainSubCategoryDefinition sub;
  final int sectionIndex;

  @override
  Widget build(BuildContext context) {
    final row = productsForSubSection(store.products, main, sub, sectionIndex);
    final allForMore = allProductsForSub(store.products, main, sub, sectionIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            sub.titleAr,
            textAlign: TextAlign.right,
            style: GoogleFonts.tajawal(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ),
        if (row.isEmpty && allForMore.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'لا توجد منتجات في هذا القسم حالياً',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 14),
            ),
          )
        else
          SizedBox(
            height: _kProductRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: row.length + (allForMore.isEmpty ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                if (i < row.length) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: CompactProductCard(store: store, product: row[i]),
                  );
                }
                return _ViewMoreTile(
                  enabled: allForMore.isNotEmpty,
                  onTap: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryFlatGridPage(
                          categoryName: '${main.titleAr} — ${sub.titleAr}',
                          presetProducts: allForMore,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
