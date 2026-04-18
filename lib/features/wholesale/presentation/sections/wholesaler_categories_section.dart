import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesaler_category_model.dart';

/// إدارة أقسام تاجر الجملة — من لوحة التحكم أو الأدمن.
class WholesalerCategoriesSection extends StatefulWidget {
  const WholesalerCategoriesSection({super.key, required this.wholesalerId});

  final String wholesalerId;

  @override
  State<WholesalerCategoriesSection> createState() => _WholesalerCategoriesSectionState();
}

class _WholesalerCategoriesSectionState extends State<WholesalerCategoriesSection> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final n = _nameCtrl.text.trim();
    if (n.isEmpty) return;
    setState(() => _saving = true);
    try {
      await WholesaleRepository.instance.upsertWholesalerCategory(
        wholesalerId: widget.wholesalerId,
        name: n,
        order: DateTime.now().millisecondsSinceEpoch % 100000,
      );
      _nameCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تمت إضافة القسم', style: GoogleFonts.tajawal())),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ القسم.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(WholesalerCategory c) async {
    final ctrl = TextEditingController(text: c.name);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل القسم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          textAlign: TextAlign.right,
          decoration: InputDecoration(labelText: 'الاسم', labelStyle: GoogleFonts.tajawal()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          FilledButton(
            onPressed: () async {
              final t = ctrl.text.trim();
              if (t.isEmpty) return;
              try {
                await WholesaleRepository.instance.upsertWholesalerCategory(
                  wholesalerId: widget.wholesalerId,
                  categoryId: c.id,
                  name: t,
                  order: c.order,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              } on Object {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تعذر تحديث القسم.', style: GoogleFonts.tajawal())),
                );
              }
            },
            child: Text('حفظ', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> _delete(WholesalerCategory c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف القسم؟', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text(
          'لن تُحذف المنتجات تلقائياً — ربّط المنتجات بأقسام أخرى إن لزم.',
          style: GoogleFonts.tajawal(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('حذف', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await WholesaleRepository.instance.deleteWholesalerCategory(
        wholesalerId: widget.wholesalerId,
        categoryId: c.id,
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حذف القسم.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'أقسام المنتجات تساعد أصحاب المتاجر على التصفح. اربط كل منتج بقسم من تبويب «المنتجات».',
            style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
            textAlign: TextAlign.right,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'اسم قسم جديد',
                    labelStyle: GoogleFonts.tajawal(),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _add,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                child: Text('إضافة', style: GoogleFonts.tajawal(color: Colors.white)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<FeatureState<List<WholesalerCategory>>>(
            stream: WholesaleRepository.instance.watchWholesalerCategories(widget.wholesalerId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('${snap.error}', style: GoogleFonts.tajawal()));
              }
              final list = switch (snap.data) {
                FeatureSuccess(:final data) => data,
                _ => <WholesalerCategory>[],
              };
              if (list.isEmpty) {
                return Center(child: Text('لا توجد أقسام بعد', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  return Card(
                    child: ListTile(
                      title: Text(c.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(c)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _delete(c),
                          ),
                        ],
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

