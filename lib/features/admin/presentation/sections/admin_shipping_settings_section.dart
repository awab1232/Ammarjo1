import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../data/admin_repository.dart';

class AdminShippingSettingsSection extends StatefulWidget {
  const AdminShippingSettingsSection({super.key});

  @override
  State<AdminShippingSettingsSection> createState() => _AdminShippingSettingsSectionState();
}

class _AdminShippingSettingsSectionState extends State<AdminShippingSettingsSection> {
  final _feeCtrl = TextEditingController();
  final _freeThresholdCtrl = TextEditingController();
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final state = await AdminRepository.instance.fetchSettings();
    if (state is! FeatureSuccess<Map<String, dynamic>>) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final s = state.data;
    _enabled = s['shippingEnabled'] != false;
    _feeCtrl.text = s['shippingFlatFee']?.toString() ?? '0';
    _freeThresholdCtrl.text = s['shippingFreeThreshold']?.toString() ?? '0';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final settingsState = await AdminRepository.instance.fetchSettings();
    if (settingsState is! FeatureSuccess<Map<String, dynamic>>) return;
    final s = settingsState.data;
    s['shippingEnabled'] = _enabled;
    s['shippingFlatFee'] = double.tryParse(_feeCtrl.text.trim()) ?? 0;
    s['shippingFreeThreshold'] = double.tryParse(_freeThresholdCtrl.text.trim()) ?? 0;
    final saveState = await AdminRepository.instance.updateSettings(s);
    if (saveState is FeatureFailure<void>) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات الشحن')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('إعدادات الشحن', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
        SwitchListTile(value: _enabled, onChanged: (v) => setState(() => _enabled = v), title: const Text('تفعيل الشحن')),
        TextField(controller: _feeCtrl, decoration: const InputDecoration(labelText: 'رسوم الشحن الثابتة')),
        TextField(controller: _freeThresholdCtrl, decoration: const InputDecoration(labelText: 'حد الشحن المجاني')),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}
