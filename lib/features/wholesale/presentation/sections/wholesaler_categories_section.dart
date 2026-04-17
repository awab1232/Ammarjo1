import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesaler_category_model.dart';

/// Ø¥Ø¯Ø§Ø±Ø© Ø£Ù‚Ø³Ø§Ù… ØªØ§Ø¬Ø± Ø§Ù„Ø¬Ù…Ù„Ø© â€” Ù…Ù† Ù„ÙˆØ­Ø© Ø§Ù„ØªØ­ÙƒÙ… Ø£Ùˆ Ø§Ù„Ø£Ø¯Ù…Ù†.
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
          SnackBar(content: Text('ØªÙ…Øª Ø¥Ø¶Ø§ÙØ© Ø§Ù„Ù‚Ø³Ù…', style: GoogleFonts.tajawal())),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ÙØ´Ù„ Ø­ÙØ¸ Ø§Ù„Ù‚Ø³Ù….', style: GoogleFonts.tajawal())),
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
        title: Text('ØªØ¹Ø¯ÙŠÙ„ Ø§Ù„Ù‚Ø³Ù…', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          textAlign: TextAlign.right,
          decoration: InputDecoration(labelText: 'Ø§Ù„Ø§Ø³Ù…', labelStyle: GoogleFonts.tajawal()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Ø¥Ù„ØºØ§Ø¡', style: GoogleFonts.tajawal())),
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
                  SnackBar(content: Text('ØªØ¹Ø°Ø± ØªØ­Ø¯ÙŠØ« Ø§Ù„Ù‚Ø³Ù….', style: GoogleFonts.tajawal())),
                );
              }
            },
            child: Text('Ø­ÙØ¸', style: GoogleFonts.tajawal(color: Colors.white)),
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
        title: Text('Ø­Ø°Ù Ø§Ù„Ù‚Ø³Ù…ØŸ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text(
          'Ù„Ù† ØªÙØ­Ø°Ù Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ â€” Ø±Ø¨Ù‘Ø· Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª Ø¨Ø£Ù‚Ø³Ø§Ù… Ø£Ø®Ø±Ù‰ Ø¥Ù† Ù„Ø²Ù….',
          style: GoogleFonts.tajawal(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Ø¥Ù„ØºØ§Ø¡', style: GoogleFonts.tajawal())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Ø­Ø°Ù', style: GoogleFonts.tajawal(color: Colors.white)),
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
          SnackBar(content: Text('ÙØ´Ù„ Ø­Ø°Ù Ø§Ù„Ù‚Ø³Ù….', style: GoogleFonts.tajawal())),
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
            'Ø£Ù‚Ø³Ø§Ù… Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª ØªØ³Ø§Ø¹Ø¯ Ø£ØµØ­Ø§Ø¨ Ø§Ù„Ù…ØªØ§Ø¬Ø± Ø¹Ù„Ù‰ Ø§Ù„ØªØµÙØ­. Ø§Ø±Ø¨Ø· ÙƒÙ„ Ù…Ù†ØªØ¬ Ø¨Ù‚Ø³Ù… Ù…Ù† ØªØ¨ÙˆÙŠØ¨ Â«Ø§Ù„Ù…Ù†ØªØ¬Ø§ØªÂ».',
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
                    labelText: 'Ø§Ø³Ù… Ù‚Ø³Ù… Ø¬Ø¯ÙŠØ¯',
                    labelStyle: GoogleFonts.tajawal(),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _add,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                child: Text('Ø¥Ø¶Ø§ÙØ©', style: GoogleFonts.tajawal(color: Colors.white)),
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
                return Center(child: Text('Ù„Ø§ ØªÙˆØ¬Ø¯ Ø£Ù‚Ø³Ø§Ù… Ø¨Ø¹Ø¯', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
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

