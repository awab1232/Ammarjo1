import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../core/contracts/feature_state.dart';

import '../../../../core/config/calculator_mapping_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../domain/calculator_service.dart';
import '../../domain/construction_calculator_models.dart';
import '../../domain/models.dart';
import '../../domain/quantity_product_mapper.dart';
import '../store_controller.dart';
import 'product_details_page.dart';

/// حاسبة الكميات — بيانات JSON + اقتراح منتجات من المتجر.
class SmartQuantityCalculatorPage extends StatefulWidget {
  const SmartQuantityCalculatorPage({super.key, this.anchorProduct});

  final Product? anchorProduct;

  @override
  State<SmartQuantityCalculatorPage> createState() => _SmartQuantityCalculatorPageState();
}

class _SmartQuantityCalculatorPageState extends State<SmartQuantityCalculatorPage> {
  CalculatorService? _svc;
  ConstructionCategory? _category;
  ConstructionItem? _item;
  final _inputCtrl = TextEditingController();
  ConstructionComputationResult? _result;
  Object? _loadError;
  /// منتجات إضافية من Woo (أقسام/وسوم) لتحسين الربط الذكي.
  List<Product> _extraCatalog = [];
  bool _mappingLoading = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final svc = await CalculatorService.instance();
      if (!mounted) return;
      final cats = svc.db.categories;
      ConstructionCategory? cat = cats.isNotEmpty ? cats.first : null;
      ConstructionItem? item = (cat != null && cat.items.isNotEmpty) ? cat.items.first : null;
      final anchor = widget.anchorProduct;
      if (anchor != null) {
        final match = _bestMatchingItem(svc, anchor);
        if (match != null) {
          var found = false;
          for (final c in cats) {
            for (final i in c.items) {
              if (i.id == match.id) {
                cat = c;
                item = match;
                found = true;
                break;
              }
            }
            if (found) break;
          }
        }
      }
      setState(() {
        _svc = svc;
        _category = cat;
        _item = item;
        _loadError = null;
      });
    } on Object {
      debugPrint('Calculator load error');
      if (!mounted) return;
      setState(() => _loadError = 'تعذر تحميل بيانات الحاسبة');
    }
  }

  ConstructionItem? _bestMatchingItem(CalculatorService svc, Product p) {
    final name = p.name.toLowerCase();
    ConstructionItem? best;
    var bestScore = 0;
    for (final c in svc.db.categories) {
      for (final i in c.items) {
        var s = 0;
        final idNorm = i.id.replaceAll('_', ' ');
        if (name.contains(idNorm)) s += 8;
        for (final part in i.nameAr.split(RegExp(r'\s+'))) {
          final t = part.replaceAll(RegExp(r'[()٠-٩0-9.]'), '').trim().toLowerCase();
          if (t.length >= 2 && name.contains(t)) s += t.length;
        }
        if (s > bestScore) {
          bestScore = s;
          best = i;
        }
      }
    }
    return bestScore >= 4 ? best : null;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  double? _parse(String s) {
    final t = s.trim().replaceAll(',', '.');
    return double.tryParse(t);
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: GoogleFonts.tajawal())));
  }

  void _calculate() {
    final item = _item;
    final svc = _svc;
    if (item == null || svc == null) return;
    final v = _parse(_inputCtrl.text);
    if (v == null || v <= 0) {
      _snack('أدخل قيمة صحيحة أكبر من صفر.');
      return;
    }
    try {
      final res = svc.compute(item: item, inputValue: v);
      setState(() => _result = res);
      final store = context.read<StoreController>();
      _syncMappingCatalog(store);
    } on ArgumentError {
      _snack('خطأ في الإدخال');
    } on Object {
      _snack('تعذر الحساب حالياً');
    }
  }

  Future<void> _syncMappingCatalog(StoreController store) async {
    final cat = _category;
    if (cat == null) return;
    final job = quantityJobKindForCalculatorCategoryId(cat.id);
    setState(() {
      _mappingLoading = true;
      _extraCatalog = [];
    });
    final extra = <Product>[];
    for (final id in CalculatorMappingConfig.wooCategoryIdsForJob(job)) {
      try {
        final state = await store.fetchProductsByCategory(id, perPage: 100);
        if (state case FeatureSuccess(:final data)) {
          extra.addAll(data);
        }
      } on Object {
        debugPrint('Failed to load mapped products by category.');
      }
    }
    final tid = CalculatorMappingConfig.tagIdForJob(job);
    if (tid != null) {
      try {
        final state = await store.fetchProductsByTag(tid, perPage: 100);
        if (state case FeatureSuccess(:final data)) {
          extra.addAll(data);
        }
      } on Object {
        debugPrint('Failed to load mapped products by tag.');
      }
    }
    if (!mounted) return;
    setState(() {
      _extraCatalog = extra;
      _mappingLoading = false;
    });
  }

  List<Product> _mergedCatalog(StoreController store) =>
      QuantityProductMapper.mergeCatalog(store.products, _extraCatalog);

  QuantityJobKind get _jobKind => quantityJobKindForCalculatorCategoryId(_category?.id ?? '');

  List<Product> _mainRecommendations(StoreController store) {
    if (_svc == null || _item == null || _result == null) return <Product>[];
    return QuantityProductMapper.pickMainProducts(
      job: _jobKind,
      item: _item!,
      result: _result!,
      catalog: _mergedCatalog(store),
    );
  }

  List<RecommendedEssential> _essentialRecommendations(StoreController store, List<Product> mainRow) {
    if (_item == null) return <RecommendedEssential>[];
    final mainIds = mainRow.map((e) => e.id).toSet();
    if (widget.anchorProduct != null) {
      mainIds.add(widget.anchorProduct!.id);
    }
    return QuantityProductMapper.pickEssentials(
      job: _jobKind,
      item: _item!,
      catalog: _mergedCatalog(store),
      excludeProductIds: mainIds,
    );
  }

  Future<void> _addAllToCart(StoreController store, List<Product> primary, List<Product> extras) async {
    final ids = <int>{};
    final all = <Product>[...primary, ...extras];
    for (final p in all) {
      if (ids.contains(p.id)) continue;
      ids.add(p.id);
      await store.addToCart(p);
    }
    if (!mounted) return;
    _snack('تمت إضافة ${ids.length} منتجاً إلى السلة');
  }

  static String _formatMaterialQty(ComputedMaterialLine l) {
    final u = l.unitLabel.toLowerCase();
    if (u.contains('piece') || u.contains('bag')) {
      return l.quantity.ceil().toString();
    }
    if (u.contains('liter')) {
      return l.quantity.toStringAsFixed(1);
    }
    return l.quantity.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text('حاسبة الكميات الذكية', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: AppColors.heading)),
      ),
      body: _buildBody(store),
    );
  }

  Widget _buildBody(StoreController store) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'تعذر تحميل بيانات الحاسبة. تحقق من وجود الملف في الأصول.',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (_svc == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    final db = _svc!.db;
    final meta = db.metadata;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'اختر البند من قاعدة البيانات الهندسية، ثم أدخل ${_item != null ? CalculatorService.inputFieldLabelAr(_item!.unit).toLowerCase() : 'القيمة'} كما في المواصفة.',
          style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.45),
        ),
        const SizedBox(height: 8),
        Text(
          'معيار: ${meta.standard} — تحديث: ${meta.lastUpdated}',
          style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: InputDecoration(labelText: 'القسم', labelStyle: GoogleFonts.tajawal(), border: const OutlineInputBorder()),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ConstructionCategory>(
              isExpanded: true,
              value: _category,
              items: db.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.nameAr, style: GoogleFonts.tajawal())))
                  .toList(),
              onChanged: (c) {
                if (c == null) return;
                setState(() {
                  _category = c;
                  _item = c.items.isNotEmpty ? c.items.first : null;
                  _result = null;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: InputDecoration(labelText: 'البند', labelStyle: GoogleFonts.tajawal(), border: const OutlineInputBorder()),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ConstructionItem>(
              isExpanded: true,
              value: _item,
              items: (_category?.items ?? const <ConstructionItem>[])
                  .map((i) => DropdownMenuItem(value: i, child: Text(i.nameAr, style: GoogleFonts.tajawal(), maxLines: 2)))
                  .toList(),
              onChanged: (i) => setState(() {
                _item = i;
                _result = null;
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_item != null) ...[
          TextField(
            controller: _inputCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: CalculatorService.inputFieldLabelAr(_item!.unit),
              helperText: 'وحدة الحساب في القاعدة: ${CalculatorService.inputUnitDescriptionAr(_item!.unit)} — هامش الهدر لهذا البند: ${(_item!.wasteFactor * 100).toStringAsFixed(0)}%',
              labelStyle: GoogleFonts.tajawal(),
              helperStyle: GoogleFonts.tajawal(fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _item == null ? null : _calculate,
          icon: const Icon(Icons.calculate_outlined),
          label: Text('احسب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        if (_result != null) _resultSection(_result!),
        if (_result != null) ..._buildSmartShoppingSection(context, store),
      ],
    );
  }

  List<Widget> _buildSmartShoppingSection(BuildContext context, StoreController store) {
    var mainRow = _mainRecommendations(store);
    final ap = widget.anchorProduct;
    if (ap != null &&
        _jobKind == QuantityJobKind.paints &&
        productIsPaintContext(ap, store) &&
        !mainRow.any((p) => p.id == ap.id)) {
      mainRow = [ap, ...mainRow];
    }
    final essentials = _essentialRecommendations(store, mainRow);

    final mainHint = switch (_jobKind) {
      QuantityJobKind.paints => 'عبوات دهان (دلو/جالون) مطابقة للحساب',
      QuantityJobKind.flooring => 'بلاط أو بورسلان أو لاصق بلاط حسب الكتالوج',
      QuantityJobKind.skeleton => 'أسمنت، حديد تسليح، أو طوب حسب البند',
      QuantityJobKind.generic => 'مواد مطابقة لنتيجة الحساب',
    };

    return [
      const SizedBox(height: 20),
      if (_mappingLoading)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'جاري تحديث المنتجات من المتجر…',
                  style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      Text('المواد الرئيسية المقترحة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.heading)),
      const SizedBox(height: 4),
      Text(mainHint, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      SizedBox(
        height: 196,
        child: mainRow.isEmpty
            ? Align(
                alignment: Alignment.centerRight,
                child: Text('لا توجد منتجات رئيسية مطابقة.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mainRow.length,
                separatorBuilder: (context, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _compactProductTile(context, store, mainRow[i]),
              ),
      ),
      const SizedBox(height: 22),
      Text('ستحتاج لهذه المستلزمات أيضاً', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.heading)),
      const SizedBox(height: 4),
      Text(
        'أدوات ومواد مكمّلة للمهمة — تُحدَّد من أقسام ووسوم WooCommerce عند ضبطها في الإعدادات.',
        style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 220,
        child: essentials.isEmpty
            ? Align(
                alignment: Alignment.centerRight,
                child: Text('لا توجد مستلزمات مطابقة في الكتالوج.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: essentials.length,
                separatorBuilder: (context, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _compactEssentialTile(context, store, essentials[i]),
              ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () {
          if (mainRow.isEmpty && essentials.isEmpty) {
            _snack('لا توجد منتجات مطابقة في الكتالوج الحالي.');
            return;
          }
          _addAllToCart(store, mainRow, essentials.map((e) => e.product).toList());
        },
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text('أضف المواد الرئيسية والمستلزمات للسلة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
    ];
  }

  Widget _compactProductTile(BuildContext context, StoreController store, Product p) {
    final imgUrl = webSafeFirstProductImage(p.images);
    return SizedBox(
      width: 158,
      child: Material(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(product: p)),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 96,
                    width: double.infinity,
                    child: imgUrl.isEmpty
                        ? ColoredBox(
                            color: AppColors.accentLight,
                            child: Icon(Icons.image_outlined, color: AppColors.accent.withValues(alpha: 0.35)),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(6),
                            child: AmmarCachedImage(
                              imageUrl: imgUrl,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              productTileStyle: true,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12, height: 1.25),
                ),
                const Spacer(),
                Text(store.formatPrice(p.price), style: GoogleFonts.tajawal(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactEssentialTile(BuildContext context, StoreController store, RecommendedEssential r) {
    final p = r.product;
    final imgUrl = webSafeFirstProductImage(p.images);
    return SizedBox(
      width: 158,
      child: Material(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(product: p)),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.roleLabelAr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tajawal(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accentDark),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 88,
                    width: double.infinity,
                    child: imgUrl.isEmpty
                        ? ColoredBox(
                            color: AppColors.accentLight,
                            child: Icon(Icons.handyman_outlined, color: AppColors.accent.withValues(alpha: 0.35)),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(6),
                            child: AmmarCachedImage(
                              imageUrl: imgUrl,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              productTileStyle: true,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12, height: 1.25),
                ),
                const Spacer(),
                Text(store.formatPrice(p.price), style: GoogleFonts.tajawal(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultSection(ConstructionComputationResult r) {
    return Card(
      margin: const EdgeInsets.only(top: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.itemNameAr, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.heading)),
            const SizedBox(height: 6),
            Text(
              'المدخلات: ${_fmtInput(r.inputValue)} ${CalculatorService.inputUnitDescriptionAr(r.inputUnitRaw)} — بعد تطبيق هامش الهدر ${(r.wasteFactor * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
            ),
            if (r.hasMaterials) ...[
              const SizedBox(height: 14),
              Text('المكوّنات المطلوبة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 8),
              ...r.materialLines.map(
                (l) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle, size: 8, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.tajawal(color: AppColors.textPrimary, height: 1.4),
                            children: [
                              TextSpan(
                                text: '${CalculatorService.materialLabelAr(l.materialKey)} (${l.labelEn}): ',
                                style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: '${_formatMaterialQty(l)} ${l.unitLabel}',
                                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.accent, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (r.hasPackages) ...[
              const SizedBox(height: 14),
              Text('العبوات (حسب التغطية المرجعية)', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                'مساحة فعّالة بعد الهدر: ${r.packageLines.first.effectiveAreaM2.toStringAsFixed(2)} م²',
                style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              ...r.packageLines.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 20, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.packageLabel, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                            Text(
                              '${p.packagesNeeded} عبوة — تغطية مرجعية ${p.coveragePerPackage} ${p.coverageUnitNote}',
                              style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, color: AppColors.accentDark, size: 22),
                      const SizedBox(width: 8),
                      Text('نصيحة الخبراء', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.heading)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(r.expertTip, style: GoogleFonts.tajawal(height: 1.45, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

String _fmtInput(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

/// يُستخدم من صفحة المنتج للتحقق إن كان المنتج ضمن سياق الدهانات.
bool productIsPaintContext(Product product, StoreController store) {
  final name = product.name.toLowerCase();
  if (name.contains('دهان') || name.contains('طلاء') || name.contains('بويه') || name.contains('معجون')) {
    return true;
  }
  for (final cid in product.categoryIds) {
    for (final c in store.categories) {
      if (c.id == cid) {
        final cn = c.name.toLowerCase();
        if (cn.contains('دهان') || cn.contains('طلاء') || cn.contains('دهانات')) return true;
      }
    }
  }
  return false;
}
