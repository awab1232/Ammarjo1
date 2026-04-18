import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/quantity_price_tier.dart';
import '../../domain/wholesale_product_model.dart';
import '../../domain/wholesaler_category_model.dart';

class WholesalerProductsPage extends StatelessWidget {
  const WholesalerProductsPage({super.key, required this.wholesalerId});

  final String wholesalerId;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        StreamBuilder<FeatureState<List<WholesaleProduct>>>(
          stream: WholesaleRepository.instance.watchWholesalerProducts(wholesalerId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.all(12),
                children: const [
                  HomeStoreListSkeleton(rows: 6),
                ],
              );
            }
            final items = switch (snap.data) {
              FeatureSuccess(:final data) => data,
              _ => <WholesaleProduct>[],
            };
            if (items.isEmpty) {
              return const EmptyStateWidget(type: EmptyStateType.products);
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final p = items[i];
                return Card(
                  child: ListTile(
                    title: Text(p.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      'الوحدة: ${p.unit} • المخزون: ${p.stock}\nالشرائح: ${p.quantityPrices.length} • المتغيرات: ${p.variants.length}',
                      style: GoogleFonts.tajawal(fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _openEditor(
                          context,
                          wholesalerId: wholesalerId,
                          existing: p,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          final confirmed = await AppBottomSheet.confirm(
                            context: context,
                            title: 'تأكيد الحذف',
                            message: 'هل أنت متأكد من حذف هذا العنصر؟',
                            confirmLabel: 'حذف',
                            isDestructive: true,
                          );
                          if (confirmed == true) {
                            await WholesaleRepository.instance.deleteWholesalerProduct(
                              wholesalerId: wholesalerId,
                              productId: p.productId,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'fab_wholesaler_add_product',
            backgroundColor: AppColors.primaryOrange,
            onPressed: () => _openEditor(context, wholesalerId: wholesalerId),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    required String wholesalerId,
    WholesaleProduct? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _WholesaleProductEditorDialog(
        wholesalerId: wholesalerId,
        existing: existing,
      ),
    );
  }
}

class _WholesaleProductEditorDialog extends StatefulWidget {
  const _WholesaleProductEditorDialog({
    required this.wholesalerId,
    this.existing,
  });

  final String wholesalerId;
  final WholesaleProduct? existing;

  @override
  State<_WholesaleProductEditorDialog> createState() =>
      _WholesaleProductEditorDialogState();
}

class _WholesaleProductEditorDialogState
    extends State<_WholesaleProductEditorDialog> {
  final _name = TextEditingController();
  final _image = TextEditingController();
  final _unit = TextEditingController();
  final _stock = TextEditingController();
  final List<(TextEditingController, TextEditingController)> _tiers = List<(TextEditingController, TextEditingController)>.empty();
  final List<_WholesaleVariantInput> _variants = List<_WholesaleVariantInput>.empty();
  bool _saving = false;
  String? _categoryId;
  bool _hasVariants = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _image.text = e.imageUrl;
      _unit.text = e.unit;
      _stock.text = e.stock.toString();
      _categoryId = e.categoryId;
      _hasVariants = e.hasVariants;
      for (final t in e.quantityPrices) {
        _tiers.add((
          TextEditingController(text: t.minQuantity.toString()),
          TextEditingController(text: t.price.toString())
        ));
      }
      for (final v in e.variants) {
        final firstOpt = v.options.isNotEmpty ? v.options.first : const <String, String>{};
        _variants.add(
          _WholesaleVariantInput(
            optionType: firstOpt['optionType'] ?? 'size',
            optionValue: firstOpt['optionValue'] ?? '',
            price: v.price.toString(),
            stock: v.stock.toString(),
            isDefault: v.isDefault,
          ),
        );
      }
    } else {
      _tiers.add((TextEditingController(), TextEditingController()));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _image.dispose();
    _unit.dispose();
    _stock.dispose();
    for (final t in _tiers) {
      t.$1.dispose();
      t.$2.dispose();
    }
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final tiers = <QuantityPriceTier>[];
    for (final t in _tiers) {
      final min = int.tryParse(t.$1.text.trim());
      final price = double.tryParse(t.$2.text.trim().replaceAll(',', '.'));
      if (min == null || price == null) continue;
      tiers.add(QuantityPriceTier(minQuantity: min, price: price));
    }
    if (!_hasVariants && tiers.isEmpty) return;
    if (_hasVariants && _variants.isEmpty) return;
    tiers.sort((a, b) => a.minQuantity.compareTo(b.minQuantity));
    final variants = _variants
        .map((v) => WholesaleVariant(
              id: v.isDefault ? 'default' : '',
              price: double.tryParse(v.price.text.trim().replaceAll(',', '.')) ?? 0,
              stock: int.tryParse(v.stock.text.trim()) ?? 0,
              isDefault: v.isDefault,
              options: [
                {
                  'optionType': v.optionType,
                  'optionValue': v.optionValue.text.trim(),
                }
              ],
            ))
        .toList();
    setState(() => _saving = true);
    try {
      final resolvedProductId = widget.existing?.productId != null && widget.existing!.productId.trim().isNotEmpty
          ? widget.existing!.productId
          : WholesaleRepository.instance.generateTempDocumentId();
      if (resolvedProductId.trim().isEmpty) {
        throw StateError('INVALID_ID');
      }
      final p = WholesaleProduct(
        productId: resolvedProductId,
        name: name,
        imageUrl: _image.text.trim(),
        unit: _unit.text.trim().isEmpty ? 'قطعة' : _unit.text.trim(),
        quantityPrices: tiers,
        stock: int.tryParse(_stock.text.trim()) ?? 0,
        categoryId: _categoryId,
        hasVariants: _hasVariants,
        variants: variants,
      );
      await WholesaleRepository.instance.upsertWholesalerProduct(
        wholesalerId: widget.wholesalerId,
        productId: resolvedProductId,
        product: p,
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'إضافة منتج جملة' : 'تعديل منتج جملة',
        style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المنتج')),
              TextField(controller: _image, decoration: const InputDecoration(labelText: 'رابط الصورة')),
              TextField(controller: _unit, decoration: const InputDecoration(labelText: 'الوحدة (كيس/متر/صندوق)')),
              TextField(controller: _stock, decoration: const InputDecoration(labelText: 'المخزون'), keyboardType: TextInputType.number),
              SwitchListTile(
                value: _hasVariants,
                onChanged: (v) => setState(() => _hasVariants = v),
                title: Text('هذا المنتج يحتوي متغيرات', style: GoogleFonts.tajawal()),
              ),
              const SizedBox(height: 8),
              StreamBuilder<FeatureState<List<WholesalerCategory>>>(
                stream: WholesaleRepository.instance.watchWholesalerCategories(widget.wholesalerId),
                builder: (context, snap) {
                  final cats = switch (snap.data) {
                    FeatureSuccess(:final data) => data,
                    _ => <WholesalerCategory>[],
                  };
                  return DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: _categoryId != null && cats.any((c) => c.id == _categoryId) ? _categoryId : null,
                    decoration: InputDecoration(labelText: 'القسم', labelStyle: GoogleFonts.tajawal()),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون قسم', style: GoogleFonts.tajawal()),
                      ),
                      ...cats.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name, style: GoogleFonts.tajawal()),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  );
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text('شرائح الكمية والسعر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              ...List.generate(_tiers.length, (i) {
                final t = _tiers[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: t.$1,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'الكمية الأدنى'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: t.$2,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'السعر'),
                        ),
                      ),
                      IconButton(
                        onPressed: _tiers.length <= 1 ? null : () => setState(() => _tiers.removeAt(i)),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _tiers.add((TextEditingController(), TextEditingController()))),
                  icon: const Icon(Icons.add),
                  label: Text('إضافة شريحة', style: GoogleFonts.tajawal()),
                ),
              ),
              if (_hasVariants) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('متغيرات المنتج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                ),
                ..._variants.asMap().entries.map((entry) {
                  final i = entry.key;
                  final v = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                // ignore: deprecated_member_use
                                value: v.optionType,
                                items: const [
                                  DropdownMenuItem(value: 'size', child: Text('Size')),
                                  DropdownMenuItem(value: 'color', child: Text('Color')),
                                  DropdownMenuItem(value: 'weight', child: Text('Weight')),
                                  DropdownMenuItem(value: 'dimension', child: Text('Dimension')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => v.optionType = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: v.optionValue,
                                decoration: const InputDecoration(labelText: 'القيمة'),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: v.price,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'السعر'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: v.stock,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'المخزون'),
                              ),
                            ),
                            Checkbox(
                              value: v.isDefault,
                              onChanged: (val) {
                                setState(() {
                                  for (final x in _variants) {
                                    x.isDefault = false;
                                  }
                                  v.isDefault = val == true;
                                });
                              },
                            ),
                            IconButton(
                              onPressed: () => setState(() => _variants.removeAt(i).dispose()),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _variants.add(
                        _WholesaleVariantInput(
                          optionType: 'size',
                          optionValue: '',
                          price: '',
                          stock: '0',
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: Text('إضافة متغير', style: GoogleFonts.tajawal()),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('إلغاء', style: GoogleFonts.tajawal())),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ', style: GoogleFonts.tajawal()),
        ),
      ],
    );
  }
}

class _WholesaleVariantInput {
  _WholesaleVariantInput({
    required this.optionType,
    required String optionValue,
    required String price,
    required String stock,
    this.isDefault = false,
  })  : optionValue = TextEditingController(text: optionValue),
        price = TextEditingController(text: price),
        stock = TextEditingController(text: stock);

  String optionType;
  final TextEditingController optionValue;
  final TextEditingController price;
  final TextEditingController stock;
  bool isDefault;

  void dispose() {
    optionValue.dispose();
    price.dispose();
    stock.dispose();
  }
}
