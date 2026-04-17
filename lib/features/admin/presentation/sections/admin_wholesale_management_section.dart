import 'package:flutter/material.dart';

import 'admin_wholesaler_requests_section.dart';
import 'admin_wholesalers_section.dart';

class AdminWholesaleManagementSection extends StatefulWidget {
  const AdminWholesaleManagementSection({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminWholesaleManagementSection> createState() => _AdminWholesaleManagementSectionState();
}

class _AdminWholesaleManagementSectionState extends State<AdminWholesaleManagementSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(controller: _tabs, tabs: const [Tab(text: 'الطلبات'), Tab(text: 'التجار')]),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              AdminWholesalerRequestsSection(),
              AdminWholesalersSection(),
            ],
          ),
        ),
      ],
    );
  }
}
