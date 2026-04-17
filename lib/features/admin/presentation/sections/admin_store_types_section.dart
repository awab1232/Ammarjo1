import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminStoreTypesSection extends StatelessWidget {
  const AdminStoreTypesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminCrudSection(
      title: 'إدارة أنواع المتاجر',
      fields: const [
        CrudFieldDef(key: 'name', label: 'الاسم', required: true),
        CrudFieldDef(key: 'key', label: 'المفتاح', required: true),
        CrudFieldDef(key: 'icon', label: 'Icon'),
        CrudFieldDef(key: 'image', label: 'Image URL'),
        CrudFieldDef(key: 'displayOrder', label: 'displayOrder'),
        CrudFieldDef(key: 'isActive', label: 'isActive (true/false)'),
      ],
      loadItems: AdminRepository.instance.fetchStoreTypes,
      onCreate: (v) => AdminRepository.instance.createStoreType(
        name: v['name'] ?? '',
        key: v['key'] ?? '',
        icon: (v['icon'] ?? '').isEmpty ? null : v['icon'],
        image: (v['image'] ?? '').isEmpty ? null : v['image'],
        displayOrder: int.tryParse(v['displayOrder'] ?? '') ?? 0,
        isActive: (v['isActive'] ?? 'true').trim().toLowerCase() != 'false',
      ),
      onUpdate: (item, v) => AdminRepository.instance.updateStoreType(
        item['id'].toString(),
        name: v['name'],
        key: v['key'],
        icon: (v['icon'] ?? '').isEmpty ? null : v['icon'],
        image: (v['image'] ?? '').isEmpty ? null : v['image'],
        displayOrder: (v['displayOrder'] ?? '').trim().isEmpty ? null : int.tryParse(v['displayOrder'] ?? ''),
        isActive: (v['isActive'] ?? '').trim().isEmpty ? null : (v['isActive']!.trim().toLowerCase() == 'true'),
      ),
      onDelete: (item) => AdminRepository.instance.deleteStoreType(item['id'].toString()),
    );
  }
}
