import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/notification_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _orders = true;
  bool _tenders = true;
  bool _offers = true;
  bool _support = true;
  bool _delivery = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orders = await NotificationPreferences.getBool(NotificationPreferences.keyOrders);
    final tenders = await NotificationPreferences.getBool(NotificationPreferences.keyTenders);
    final offers = await NotificationPreferences.getBool(NotificationPreferences.keyOffers);
    final support = await NotificationPreferences.getBool(NotificationPreferences.keySupport);
    final delivery = await NotificationPreferences.getBool(NotificationPreferences.keyDelivery);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _tenders = tenders;
      _offers = offers;
      _support = support;
      _delivery = delivery;
      _loading = false;
    });
  }

  Future<void> _set(String key, bool value) async {
    await NotificationPreferences.setBool(key, value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الإعدادات', style: GoogleFonts.tajawal())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: const AppBarBackButton(),
        title: Text('إعدادات الإشعارات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  value: _orders,
                  title: Text('إشعارات الطلبات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  onChanged: (v) async {
                    setState(() => _orders = v);
                    await _set(NotificationPreferences.keyOrders, v);
                  },
                ),
                SwitchListTile(
                  value: _tenders,
                  title: Text('إشعارات المناقصات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  onChanged: (v) async {
                    setState(() => _tenders = v);
                    await _set(NotificationPreferences.keyTenders, v);
                  },
                ),
                SwitchListTile(
                  value: _offers,
                  title: Text('إشعارات العروض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  onChanged: (v) async {
                    setState(() => _offers = v);
                    await _set(NotificationPreferences.keyOffers, v);
                  },
                ),
                SwitchListTile(
                  value: _support,
                  title: Text('إشعارات الدعم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  onChanged: (v) async {
                    setState(() => _support = v);
                    await _set(NotificationPreferences.keySupport, v);
                  },
                ),
                SwitchListTile(
                  value: _delivery,
                  title: Text('إشعارات التوصيل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  onChanged: (v) async {
                    setState(() => _delivery = v);
                    await _set(NotificationPreferences.keyDelivery, v);
                  },
                ),
              ],
            ),
    );
  }
}
