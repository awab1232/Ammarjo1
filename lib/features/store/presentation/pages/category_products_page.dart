import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../domain/models.dart';
import '../store_controller.dart';
import '../widgets/compact_product_card.dart';
import '../widgets/store_category_avatar.dart';
import 'category_flat_grid_page.dart';

/// خلفية الصفحة — رمادي فاتح جداً.
const Color _kPageBackground = Color(0xFFF3F4F6);

/// خط تحت العنوان (برتقالي + لمسة ذهبية).
const List<Color> _kTitleUnderlineGradient = [Color(0xFFFF6B35), Color(0xFFE8A317)];

/// صفحة تفاصيل قسم: عنوان رئيسي، سلايدر أقسام فرعية، ثم أقسام عمودية بعشرة منتجات لكل فرع.
class CategoryProductsPage extends StatefulWidget {
  final int categoryId;
  final String categoryName;

  const CategoryProductsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  List<ProductCategory> _children = List<ProductCategory>.empty();
  final Map<int, List<Product>> _productsBySub = {};
  List<Product> _parentOnlyProducts = List<Product>.empty();
  var _loading = true;
  String? _error;
  int? _highlightedSubId;

  final Map<int, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = context.read<StoreController>();
      final childrenState = await store.fetchChildCategories(widget.categoryId);
      final children = switch (childrenState) {
        FeatureSuccess(:final data) => data,
        _ => List<ProductCategory>.empty(),
      };

      if (children.isEmpty) {
        final allState = await store.fetchProductsByCategory(widget.categoryId, perPage: 100);
        final all = switch (allState) {
          FeatureSuccess(:final data) => data,
          _ => List<Product>.empty(),
        };
        if (!mounted) return;
        setState(() {
          _children = List<ProductCategory>.empty();
          _parentOnlyProducts = all;
          _productsBySub.clear();
          _loading = false;
        });
        return;
      }

      final listStates = await Future.wait(children.map((c) => store.fetchProductsByCategory(c.id, perPage: 10)));

      if (!mounted) return;
      final keys = <int, GlobalKey>{};
      for (final c in children) {
        keys[c.id] = GlobalKey();
      }
      final map = <int, List<Product>>{};
      for (var i = 0; i < children.length; i++) {
        map[children[i].id] = switch (listStates[i]) {
          FeatureSuccess(:final data) => data,
          _ => List<Product>.empty(),
        };
      }

      setState(() {
        _children = children;
        _productsBySub
          ..clear()
          ..addAll(map);
        _parentOnlyProducts = List<Product>.empty();
        _sectionKeys
          ..clear()
          ..addAll(keys);
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل بيانات القسم.';
        _loading = false;
      });
    }
  }

  void _scrollToSub(int id) {
    setState(() => _highlightedSubId = id);
    final key = _sectionKeys[id];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    }
  }

  Future<void> _showProductQuickPreview(BuildContext context, Product product, StoreController store) async {
    await AppBottomSheet.show<void>(
      context: context,
      title: 'معاينة سريعة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: AppColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.inventory_2_outlined, size: 52, color: AppColors.accent),
          ),
          const SizedBox(height: 12),
          Text(product.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            store.formatPrice(product.price),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.primaryOrange, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
            onPressed: () async {
              await store.addToCart(product);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المنتج إلى السلة')));
              }
            },
            child: const Text('إضافة إلى السلة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();

    return Scaffold(
      backgroundColor: _kPageBackground,
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _load,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ammarShimmerWrap(
                      child: Container(
                        height: 36,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const ProductGridShimmer(childAspectRatio: 0.65, itemCount: 8),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.tajawal(fontSize: 15, height: 1.4),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _load,
                                style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                                child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _MainHeader(title: widget.categoryName)),
                      if (_children.isNotEmpty) SliverToBoxAdapter(child: _SubCategorySlider(
                        categories: _children,
                        highlightedId: _highlightedSubId,
                        onTap: _scrollToSub,
                      )),
                      if (_children.isEmpty)
                        SliverToBoxAdapter(child: _ParentOnlyBody(
                          products: _parentOnlyProducts,
                          categoryId: widget.categoryId,
                          categoryName: widget.categoryName,
                          store: store,
                        ))
                      else
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 32),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final sub = _children[index];
                                final products = _productsBySub[sub.id] != null ? _productsBySub[sub.id]! : List<Product>.empty();
                                return _SubcategorySection(
                                  key: _sectionKeys[sub.id],
                                  sub: sub,
                                  products: products,
                                  store: store,
                                );
                              },
                              childCount: _children.length,
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _MainHeader extends StatelessWidget {
  final String title;
  const _MainHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.orange.withValues(alpha: 0.95),
            AppColors.navy.withValues(alpha: 0.92),
          ],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 20),
          child: Row(
            children: [
              BackButton(color: Colors.white),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubCategorySlider extends StatelessWidget {
  final List<ProductCategory> categories;
  final int? highlightedId;
  final ValueChanged<int> onTap;

  const _SubCategorySlider({
    required this.categories,
    required this.highlightedId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'الأقسام الفرعية',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 102,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final c = categories[i];
                final selected = highlightedId == c.id;
                return Material(
                  color: Colors.white,
                  elevation: selected ? 4 : 2,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => onTap(c.id),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 88,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? AppColors.orange : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          StoreCategoryAvatar(
                            imageUrl: c.imageUrl.trim().isEmpty ? null : c.imageUrl,
                            size: 56,
                            borderRadius: 12,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                              color: selected ? AppColors.orange : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubcategorySection extends StatelessWidget {
  final ProductCategory sub;
  final List<Product> products;
  final StoreController store;

  const _SubcategorySection({
    super.key,
    required this.sub,
    required this.products,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final useWebGrid = kIsWeb && width > 800;
    final crossAxisCount = width > 1200 ? 5 : width > 900 ? 4 : 3;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        sub.name,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          height: 3,
                          width: 72,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: _kTitleUnderlineGradient),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryFlatGridPage(
                          categoryId: sub.id,
                          categoryName: sub.name,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text(
                    'عرض المزيد',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: EmptyStateWidget(type: EmptyStateType.products),
            )
          else
            useWebGrid
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.builder(
                      itemCount: products.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.75,
                      ),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => (context.findAncestorStateOfType<_CategoryProductsPageState>())
                            ?._showProductQuickPreview(context, products[i], store),
                        child: CompactProductCard(store: store, product: products[i]),
                      ),
                    ),
                  )
                : SizedBox(
                    height: 300,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => (context.findAncestorStateOfType<_CategoryProductsPageState>())
                            ?._showProductQuickPreview(context, products[i], store),
                        child: CompactProductCard(store: store, product: products[i]),
                      ),
                    ),
                  ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// عندما لا توجد أقسام فرعية: عرض أول 10 + عرض المزيد للشبكة الكاملة.
class _ParentOnlyBody extends StatelessWidget {
  final List<Product> products;
  final int categoryId;
  final String categoryName;
  final StoreController store;

  const _ParentOnlyBody({
    required this.products,
    required this.categoryId,
    required this.categoryName,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final preview = products.length > 10 ? products.sublist(0, 10) : products;
    final width = MediaQuery.of(context).size.width;
    final useWebGrid = kIsWeb && width > 800;
    final crossAxisCount = width > 1200 ? 5 : width > 900 ? 4 : 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'المنتجات',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          height: 3,
                          width: 72,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: _kTitleUnderlineGradient),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CategoryFlatGridPage(
                          categoryId: categoryId,
                          categoryName: categoryName,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.orange),
                  child: const Text(
                    'عرض المزيد',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.orange,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (preview.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: EmptyStateWidget(type: EmptyStateType.products),
            )
          else
            useWebGrid
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.builder(
                      itemCount: preview.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.75,
                      ),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => (context.findAncestorStateOfType<_CategoryProductsPageState>())
                            ?._showProductQuickPreview(context, preview[i], store),
                        child: CompactProductCard(store: store, product: preview[i]),
                      ),
                    ),
                  )
                : SizedBox(
                    height: 300,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: preview.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => (context.findAncestorStateOfType<_CategoryProductsPageState>())
                            ?._showProductQuickPreview(context, preview[i], store),
                        child: CompactProductCard(store: store, product: preview[i]),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
