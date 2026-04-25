import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';

class AdminNotificationsSection extends StatefulWidget {
  const AdminNotificationsSection({super.key});

  @override
  State<AdminNotificationsSection> createState() => _AdminNotificationsSectionState();
}

class _AdminNotificationsSectionState extends State<AdminNotificationsSection> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _targetRole = '';
  bool _sending = false;

  static const _targets = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: '', child: Text('كل المستخدمين')),
    DropdownMenuItem(value: 'customer', child: Text('العملاء فقط')),
    DropdownMenuItem(value: 'store_owner', child: Text('أصحاب المتاجر')),
    DropdownMenuItem(value: 'technician', child: Text('الفنيون')),
    DropdownMenuItem(value: 'driver', child: Text('السائقون')),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('العنوان والنص مطلوبان', style: GoogleFonts.tajawal())),
      );
      return;
    }
    setState(() => _sending = true);
    final res = await AdminRepository.instance.broadcastNotification(
      title: title,
      body: body,
      targetRole: _targetRole.isEmpty ? null : _targetRole,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    switch (res) {
      case FeatureSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال الإشعار بنجاح', style: GoogleFonts.tajawal())),
        );
      case FeatureFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
        );
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إرسال الإشعار', style: GoogleFonts.tajawal())),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('إرسال إشعار جماعي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: 'عنوان الإشعار', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bodyCtrl,
          minLines: 3,
          maxLines: 5,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: 'نص الإشعار', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _targetRole,
          items: _targets,
          onChanged: (v) => setState(() => _targetRole = v ?? ''),
          decoration: const InputDecoration(labelText: 'الفئة المستهدفة', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('معاينة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text(_titleCtrl.text.trim().isEmpty ? 'عنوان الإشعار' : _titleCtrl.text.trim(), style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(_bodyCtrl.text.trim().isEmpty ? 'نص الإشعار' : _bodyCtrl.text.trim(), style: GoogleFonts.tajawal()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send_rounded),
          label: Text(_sending ? 'جاري الإرسال...' : 'إرسال', style: GoogleFonts.tajawal()),
        ),
      ],
    );
  }
}
