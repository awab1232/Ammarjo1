import 'package:flutter/material.dart';

import '../sections/admin_boost_requests_section.dart';
import '../sections/admin_featured_stores_section.dart';
import '../sections/admin_home_sections_section.dart';
import '../sections/admin_store_categories_section.dart';
import '../sections/admin_store_requests_section.dart';
import '../sections/admin_store_types_section.dart';
import '../sections/admin_sub_categories_section.dart';

class AdminStoresScreen extends StatelessWidget {
  const AdminStoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Column(
        children: const [
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'طلبات المتاجر'),
              Tab(text: 'تصنيفات المتاجر'),
              Tab(text: 'الأقسام الرئيسية'),
              Tab(text: 'الأقسام الفرعية'),
              Tab(text: 'أنواع المتاجر'),
              Tab(text: 'المتاجر المميزة'),
              Tab(text: 'طلبات الترويج'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                AdminStoreRequestsSection(),
                AdminStoreCategoriesSection(),
                AdminHomeSectionsSection(),
                AdminSubCategoriesSection(),
                AdminStoreTypesSection(),
                AdminFeaturedStoresSection(),
                AdminBoostRequestsSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
