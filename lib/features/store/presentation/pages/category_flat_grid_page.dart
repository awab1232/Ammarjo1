import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../domain/models.dart';
import '../../domain/product_derived_categories.dart';
import '../store_controller.dart';
import '../widgets/store_product_card.dart';

/// شبكة منتجات كاملة لقسم واحد (لـ «عرض المزيد»).
/// إما [presetProducts] جاهزة من الشاشة السابقة، أو [categoryId] من Woo/Firestore، أو [matchCategoryLabel] لحقول المنتج.
class CategoryFlatGridPage extends StatefulWidget {
  final String categoryName;
  final int? categoryId;
  final String? matchCategoryLabel;
  final List<Product>? presetProducts;

  const CategoryFlatGridPage({
    super.key,
    required this.categoryName,
    this.categoryId,
    this.matchCategoryLabel,
    this.presetProducts,
  });

  @override
  State<CategoryFlatGridPage> createState() => _CategoryFlatGridPageState();
}

class _CategoryFlatGridPageState extends State<CategoryFlatGridPage> {
  List<Product> _products = [];
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final preset = widget.presetProducts;
    if (preset != null) {
      _products = List<Product>.from(preset);
      _loading = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final isPreset = widget.presetProducts != null;
    if (!isPreset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final store = context.read<StoreController>();
      final List<Product> list;
      final preset = widget.presetProducts;
      if (preset != null) {
        if (preset.isEmpty) {
          list = [];
        } else {
          final byId = {for (final p in store.products) p.id: p};
          list = [
            for (final p in preset)
              if (byId.containsKey(p.id)) byId[p.id]! else p,
          ];
        }
      } else {
        final label = widget.matchCategoryLabel?.trim();
        if (label != null && label.isNotEmpty) {
          list = productsMatchingCategoryLabel(store.products, label);
        } else if (widget.categoryId != null && widget.categoryId! > 0) {
          final state = await store.fetchProductsByCategory(widget.categoryId!, perPage: 100);
          list = switch (state) {
            FeatureSuccess(:final data) => data,
            _ => <Product>[],
          };
        } else {
          list = [];
        }
      }
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'unexpected error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0.5,
        centerTitle: true,
        leading: const AppBarBackButton(),
        title: Text(
          widget.categoryName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(_error!)))],
                  )
                : _products.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('لا توجد منتجات', style: TextStyle(color: AppColors.textSecondary))),
                        ],
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _products.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.58,
                        ),
                        itemBuilder: (context, i) => StoreProductCard(store: store, product: _products[i]),
                      ),
      ),
    );
  }
}
