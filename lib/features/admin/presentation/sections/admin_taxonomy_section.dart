import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminTaxonomySection extends StatelessWidget {
  const AdminTaxonomySection({
    super.key,
    required this.title,
    required this.kind,
    this.includeKindField = false,
  });

  final String title;
  final String kind;
  final bool includeKindField;

  @override
  Widget build(BuildContext context) {
    return AdminCrudSection(
      title: title,
      fields: [
        const CrudFieldDef(key: 'name', label: 'الاسم', required: true),
        if (includeKindField)
          const CrudFieldDef(key: 'kind', label: 'النوع', readItemKey: 'kind'),
        const CrudFieldDef(key: 'status', label: 'الحالة'),
      ],
      loadItems: () => AdminRepository.instance.fetchCategories(kind: kind),
      onCreate: (v) => AdminRepository.instance.createCategory(
        name: v['name'] ?? '',
        kind: includeKindField ? ((v['kind']?.isEmpty ?? true) ? kind : v['kind']!) : kind,
        status: (v['status']?.isEmpty ?? true) ? 'active' : v['status']!,
      ),
      onUpdate: (item, v) => AdminRepository.instance.updateCategory(
        item['id'].toString(),
        name: v['name'],
        kind: includeKindField ? v['kind'] : null,
        status: v['status'],
      ),
      onDelete: (item) => AdminRepository.instance.deleteCategory(item['id'].toString()),
    );
  }
}
