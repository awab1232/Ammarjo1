import 'package:flutter/material.dart';

import 'admin_taxonomy_section.dart';

class AdminStoreCategoriesSection extends StatelessWidget {
  const AdminStoreCategoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminTaxonomySection(
      title: 'أقسام المتاجر',
      kind: 'store',
    );
  }
}
