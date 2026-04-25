import 'package:flutter/material.dart';

import 'admin_taxonomy_section.dart';

class AdminTechSpecialtiesSection extends StatelessWidget {
  const AdminTechSpecialtiesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminTaxonomySection(
      title: 'تخصصات الفنيين',
      kind: 'tech',
      includeImageField: true,
    );
  }
}
