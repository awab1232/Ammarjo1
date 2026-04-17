import 'package:flutter/material.dart';

import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../data/admin_repository.dart';

class AdminEmailSettingsSection extends StatefulWidget {
  const AdminEmailSettingsSection({super.key});

  @override
  State<AdminEmailSettingsSection> createState() => _AdminEmailSettingsSectionState();
}

class _AdminEmailSettingsSectionState extends State<AdminEmailSettingsSection> {
  final _fromCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  bool _enabled = false;
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
    _enabled = s['emailEnabled'] == true;
    _fromCtrl.text = s['emailFrom']?.toString() ?? '';
    _hostCtrl.text = s['emailHost']?.toString() ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final settingsState = await AdminRepository.instance.fetchSettings();
    if (settingsState is! FeatureSuccess<Map<String, dynamic>>) return;
    final s = settingsState.data;
    s['emailEnabled'] = _enabled;
    s['emailFrom'] = _fromCtrl.text.trim();
    s['emailHost'] = _hostCtrl.text.trim();
    final saveState = await AdminRepository.instance.updateSettings(s);
    if (saveState is FeatureFailure<void>) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('إعدادات البريد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
        SwitchListTile(value: _enabled, onChanged: (v) => setState(() => _enabled = v), title: const Text('تفعيل البريد')),
        TextField(controller: _fromCtrl, decoration: const InputDecoration(labelText: 'مرسل البريد')),
        TextField(controller: _hostCtrl, decoration: const InputDecoration(labelText: 'SMTP Host')),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}
