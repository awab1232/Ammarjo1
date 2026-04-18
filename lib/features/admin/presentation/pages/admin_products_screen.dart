import 'package:flutter/material.dart';

import '../sections/admin_products_boost_section.dart';
import '../sections/admin_products_section.dart';

abstract final class AdminProductsTabIndex {
  static const int products = 0;
  static const int productBoost = 1;
}

class AdminProductsScreen extends StatelessWidget {
  const AdminProductsScreen({super.key, this.initialTab = 0});

  /// 0 = المنتجات، 1 = Boost المنتجات.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final safeTab = initialTab.clamp(0, 1);
    return DefaultTabController(
      length: 2,
      initialIndex: safeTab,
      child: Column(
        children: const [
          TabBar(
            tabs: [
              Tab(text: 'المنتجات'),
              Tab(text: 'Boost المنتجات'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                AdminProductsSection(),
                AdminProductsBoostSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
