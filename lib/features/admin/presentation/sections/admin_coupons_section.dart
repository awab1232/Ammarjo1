import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminCouponsSection extends StatelessWidget {
  const AdminCouponsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminCrudSection(
      title: 'إدارة الكوبونات',
      fields: const [
        CrudFieldDef(key: 'code', label: 'الكود', required: true),
        CrudFieldDef(key: 'name', label: 'الاسم', required: true),
        CrudFieldDef(key: 'status', label: 'الحالة', readItemKey: 'status'),
      ],
      loadItems: AdminRepository.instance.fetchCoupons,
      onCreate: (v) => AdminRepository.instance.createCoupon(
        code: v['code'] ?? '',
        name: v['name'] ?? '',
        status: (v['status']?.isEmpty ?? true) ? 'active' : v['status']!,
      ),
      onUpdate: (item, v) => AdminRepository.instance.updateCoupon(
        item['id'].toString(),
        code: v['code'],
        name: v['name'],
        status: v['status'],
      ),
      onDelete: (item) => AdminRepository.instance.deleteCoupon(item['id'].toString()),
    );
  }
}
