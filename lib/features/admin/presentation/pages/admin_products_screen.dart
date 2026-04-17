import 'package:flutter/material.dart';

import '../sections/admin_products_boost_section.dart';
import '../sections/admin_products_section.dart';

class AdminProductsScreen extends StatelessWidget {
  const AdminProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
