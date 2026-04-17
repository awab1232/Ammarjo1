import 'package:flutter/material.dart';

import 'admin_taxonomy_section.dart';

class AdminCategoriesSection extends StatelessWidget {
  const AdminCategoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminTaxonomySection(
      title: 'إدارة الأقسام',
      kind: 'general',
      includeKindField: true,
    );
  }
}
