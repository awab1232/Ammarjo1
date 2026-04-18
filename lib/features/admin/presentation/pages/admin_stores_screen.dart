import 'package:flutter/material.dart';

import '../sections/admin_boost_requests_section.dart';
import '../sections/admin_featured_stores_section.dart';
import '../sections/admin_home_sections_section.dart';
import '../sections/admin_store_categories_section.dart';
import '../sections/admin_store_requests_section.dart';
import '../sections/admin_store_types_section.dart';
import '../sections/admin_sub_categories_section.dart';

/// فهارس تبويبات [AdminStoresScreen] — يجب أن تطابق ترتيب [TabBar] و [TabBarView].
abstract final class AdminStoresTabIndex {
  static const int storeRequests = 0;
  static const int storeCategories = 1;
  static const int homeSections = 2;
  static const int subCategories = 3;
  static const int storeTypes = 4;
  static const int featuredStores = 5;
  static const int boostRequests = 6;
}

class AdminStoresScreen extends StatelessWidget {
  const AdminStoresScreen({super.key, this.initialTab = 0});

  /// فهرس التبويبة (0–6) المطابقة لترتيب [TabBar].
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final safeTab = initialTab.clamp(0, 6);
    return DefaultTabController(
      length: 7,
      initialIndex: safeTab,
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
