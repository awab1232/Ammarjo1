import 'package:flutter/material.dart';

import '../sections/admin_coupons_section.dart';
import '../sections/admin_promotions_section.dart';

class AdminPromotionsScreen extends StatelessWidget {
  const AdminPromotionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: const [
          TabBar(
            tabs: [
              Tab(text: 'العروض'),
              Tab(text: 'أكواد الخصم'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                AdminPromotionsSection(),
                AdminCouponsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
