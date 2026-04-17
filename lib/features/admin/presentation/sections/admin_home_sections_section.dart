import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminHomeSectionsSection extends StatelessWidget {
  const AdminHomeSectionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminCrudSection(
      title: 'إدارة الأقسام الرئيسية',
      fields: const [
        CrudFieldDef(key: 'storeTypeId', label: 'Store Type ID', readItemKey: 'storeTypeId'),
        CrudFieldDef(key: 'name', label: 'الاسم', required: true),
        CrudFieldDef(key: 'type', label: 'النوع (stores/services/technicians)', required: true),
        CrudFieldDef(key: 'image', label: 'الصورة'),
        CrudFieldDef(key: 'isActive', label: 'isActive (true/false)', readItemKey: 'is_active'),
      ],
      loadItems: () => AdminRepository.instance.fetchHomeSections(),
      onCreate: (v) => AdminRepository.instance.createHomeSection(
        name: v['name'] ?? '',
        type: v['type'] ?? '',
        storeTypeId: (v['storeTypeId'] ?? '').trim().isEmpty ? null : v['storeTypeId'],
        image: (v['image'] ?? '').isEmpty ? null : v['image'],
        isActive: (v['isActive'] ?? 'true').trim().toLowerCase() != 'false',
      ),
      onUpdate: (item, v) => AdminRepository.instance.updateHomeSection(
        item['id'].toString(),
        storeTypeId: (v['storeTypeId'] ?? '').trim().isEmpty ? null : v['storeTypeId'],
        name: v['name'],
        type: v['type'],
        image: (v['image'] ?? '').isEmpty ? null : v['image'],
        isActive: (v['isActive'] ?? '').trim().isEmpty ? null : (v['isActive']!.trim().toLowerCase() == 'true'),
      ),
      onDelete: (item) => AdminRepository.instance.deleteHomeSection(item['id'].toString()),
    );
  }
}
