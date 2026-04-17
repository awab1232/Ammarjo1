import 'package:flutter/material.dart';

import '../sections/admin_commission_settings_section.dart';
import '../sections/admin_email_settings_section.dart';
import '../sections/admin_shipping_settings_section.dart';

class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: const [
          TabBar(
            tabs: [
              Tab(text: 'الشحن'),
              Tab(text: 'البريد'),
              Tab(text: 'العمولة العامة'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                AdminShippingSettingsSection(),
                AdminEmailSettingsSection(),
                AdminCommissionSettingsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
