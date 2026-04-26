import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';

class AdminCommissionPerCategorySection extends StatefulWidget {
  const AdminCommissionPerCategorySection({super.key});

  @override
  State<AdminCommissionPerCategorySection> createState() =>
      _AdminCommissionPerCategorySectionState();
}

class _AdminCommissionPerCategorySectionState
    extends State<AdminCommissionPerCategorySection> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = List<Map<String, dynamic>>.empty(
    growable: false,
  );
  final Map<String, TextEditingController> _commissionCtrls =
      <String, TextEditingController>{};
  final Set<String> _savingIds = <String>{};

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
        for (final c in _commissionCtrls.values) {
          c.dispose();
        }
        _commissionCtrls.clear();
        for (final row in data) {
          final id = row['id']?.toString().trim() ?? '';
          if (id.isEmpty) continue;
          final payload = row['payload'];
          final map = payload is Map
              ? Map<String, dynamic>.from(payload)
              : <String, dynamic>{};
          final pct = (map['commissionPercent'] as num?)?.toDouble() ?? 0;
          _commissionCtrls[id] = TextEditingController(
            text: pct.toStringAsFixed(2),
          );
        }
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

  @override
  void dispose() {
    for (final c in _commissionCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveRow(Map<String, dynamic> row) async {
    final id = row['id']?.toString().trim() ?? '';
    if (id.isEmpty || _savingIds.contains(id)) return;
    final ctrl = _commissionCtrls[id];
    if (ctrl == null) return;
    final pct = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    if (pct == null || pct < 0 || pct > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'أدخل نسبة صحيحة بين 0 و 100',
            style: GoogleFonts.tajawal(),
          ),
        ),
      );
      return;
    }
    setState(() => _savingIds.add(id));
    final res = await AdminRepository.instance.patchCategoryCommission(
      id,
      commissionPercent: pct,
    );
    if (!mounted) return;
    setState(() => _savingIds.remove(id));
    if (!mounted) return;
    switch (res) {
      case FeatureSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديث نسبة العمولة',
              style: GoogleFonts.tajawal(),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _load();
      case FeatureFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
        );
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تحديث النسبة', style: GoogleFonts.tajawal()),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.orange),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: GoogleFonts.tajawal(color: AppColors.error),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final row = _items[i];
          final id = row['id']?.toString().trim() ?? '';
          final payload = row['payload'];
          final map = payload is Map
              ? Map<String, dynamic>.from(payload)
              : <String, dynamic>{};
          final pct = (map['commissionPercent'] as num?)?.toDouble() ?? 0;
          final ctrl = _commissionCtrls[id];
          if (ctrl == null) return const SizedBox.shrink();
          final saving = _savingIds.contains(id);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    row['name']?.toString() ?? '—',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'النسبة الحالية: ${pct.toStringAsFixed(2)}%',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving ? null : () => _saveRow(row),
                          child: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text('حفظ', style: GoogleFonts.tajawal()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: ctrl,
                          enabled: !saving,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'نسبة العمولة %',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
