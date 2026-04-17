import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';

class AdminCommissionSettingsSection extends StatefulWidget {
  const AdminCommissionSettingsSection({super.key});

  @override
  State<AdminCommissionSettingsSection> createState() =>
      _AdminCommissionSettingsSectionState();
}

class _AdminCommissionSettingsSectionState
    extends State<AdminCommissionSettingsSection> {
  final TextEditingController _commissionCtrl = TextEditingController();
  final TextEditingController _byStoreTypeCtrl = TextEditingController();
  final TextEditingController _byCategoryCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commissionCtrl.dispose();
    _byStoreTypeCtrl.dispose();
    _byCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await AdminRepository.instance.fetchSettings();
    if (!mounted) return;
    if (state case FeatureSuccess(:final data)) {
      final value = (data['globalCommissionPercent'] as num?)?.toDouble() ?? 12.0;
      _commissionCtrl.text = value.toStringAsFixed(2);
      _byStoreTypeCtrl.text = jsonEncode(data['commissionByStoreType'] ?? <String, dynamic>{});
      _byCategoryCtrl.text = jsonEncode(data['commissionByCategory'] ?? <String, dynamic>{});
    }
  }

  Future<void> _save() async {
    final v = double.tryParse(_commissionCtrl.text.trim());
    if (v == null || v < 0 || v > 100) {
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
    Map<String, dynamic> byStoreType;
    Map<String, dynamic> byCategory;
    try {
      byStoreType = (_byStoreTypeCtrl.text.trim().isEmpty
              ? <String, dynamic>{}
              : jsonDecode(_byStoreTypeCtrl.text.trim()))
          as Map<String, dynamic>;
      byCategory = (_byCategoryCtrl.text.trim().isEmpty
              ? <String, dynamic>{}
              : jsonDecode(_byCategoryCtrl.text.trim()))
          as Map<String, dynamic>;
    } on Object {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('صيغة JSON غير صحيحة في حقول العمولة المتقدمة', style: GoogleFonts.tajawal())),
      );
      return;
    }

    setState(() => _saving = true);
    final state = await AdminRepository.instance.updateSettings(<String, dynamic>{
      'globalCommissionPercent': v,
      'commissionByStoreType': byStoreType,
      'commissionByCategory': byCategory,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (state case FeatureFailure(:final message)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تحديث نسبة العمولة العامة',
          style: GoogleFonts.tajawal(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Commission Settings',
                style: GoogleFonts.tajawal(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.right,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _commissionCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Global commission %',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _byStoreTypeCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'commissionByStoreType (JSON)',
                  border: OutlineInputBorder(),
                  hintText: '{"retail": 10, "wholesale": 5}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _byCategoryCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'commissionByCategory (JSON)',
                  border: OutlineInputBorder(),
                  hintText: '{"construction": 10, "home_tools": 8}',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                child: Text(
                  _saving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
                  style: GoogleFonts.tajawal(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
