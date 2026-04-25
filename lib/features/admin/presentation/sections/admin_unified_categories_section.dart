import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_categories_section.dart';
import 'admin_store_categories_section.dart';
import 'admin_sub_categories_section.dart';

class AdminUnifiedCategoriesSection extends StatelessWidget {
  const AdminUnifiedCategoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('إدارة الأقسام والتصنيفات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(child: Text('الأقسام الرئيسية', style: GoogleFonts.tajawal())),
              Tab(child: Text('تصنيفات المتاجر', style: GoogleFonts.tajawal())),
              Tab(child: Text('الأقسام الفرعية', style: GoogleFonts.tajawal())),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                AdminCategoriesSection(),
                AdminStoreCategoriesSection(),
                AdminSubCategoriesSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
