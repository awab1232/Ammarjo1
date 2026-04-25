import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';

class AdminCommissionPerCategorySection extends StatefulWidget {
  const AdminCommissionPerCategorySection({super.key});

  @override
  State<AdminCommissionPerCategorySection> createState() => _AdminCommissionPerCategorySectionState();
}

class _AdminCommissionPerCategorySectionState extends State<AdminCommissionPerCategorySection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = List<Map<String, dynamic>>.empty(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final st = await AdminRepository.instance.fetchCategories(kind: 'all');
    if (!mounted) return;
    switch (st) {
      case FeatureSuccess(:final data):
        setState(() {
          _items = data;
          _loading = false;
        });
      case FeatureFailure(:final message):
        setState(() {
          _error = message;
          _loading = false;
        });
      default:
        setState(() {
          _error = 'تعذر تحميل التصنيفات';
          _loading = false;
        });
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final payload = row['payload'];
    final map = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    final current = (map['commissionPercent'] as num?)?.toDouble() ?? 0;
    final ctrl = TextEditingController(text: current.toStringAsFixed(current.truncateToDouble() == current ? 0 : 2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل العمولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'نسبة العمولة %', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final pct = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    if (pct == null) return;
    final res = await AdminRepository.instance.patchCategoryCommission(
      row['id']?.toString() ?? '',
      commissionPercent: pct,
    );
    if (!mounted) return;
    switch (res) {
      case FeatureSuccess():
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ النسبة', style: GoogleFonts.tajawal())));
        _load();
      case FeatureFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.tajawal())));
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث النسبة', style: GoogleFonts.tajawal())),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.orange));
    if (_error != null) {
      return Center(child: Text(_error!, style: GoogleFonts.tajawal(color: AppColors.error)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final row = _items[i];
          final payload = row['payload'];
          final map = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
          final pct = (map['commissionPercent'] as num?)?.toDouble() ?? 0;
          return Card(
            child: ListTile(
              title: Text(row['name']?.toString() ?? '—', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              subtitle: Text('العمولة الحالية: ${pct.toStringAsFixed(2)}%', style: GoogleFonts.tajawal()),
              trailing: OutlinedButton(
                onPressed: () => _edit(row),
                child: Text('تعديل', style: GoogleFonts.tajawal()),
              ),
            ),
          );
        },
      ),
    );
  }
}
