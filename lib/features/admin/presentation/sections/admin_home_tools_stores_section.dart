import 'package:flutter/material.dart';

import '../../../stores/domain/store_category_kind.dart';
import 'admin_store_requests_section.dart';

/// إدارة طلبات ومتاجر «الأدوات المنزلية» — نفس واجهة [AdminStoreRequestsSection] مع تصفية [StoreCategoryKind.homeTools].
class AdminHomeToolsStoresSection extends StatelessWidget {
  const AdminHomeToolsStoresSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminStoreRequestsSection(categoryFilter: StoreCategoryKind.homeTools);
  }
}
