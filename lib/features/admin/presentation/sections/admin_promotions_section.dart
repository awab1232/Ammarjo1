import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminPromotionsSection extends StatelessWidget {
  const AdminPromotionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminCrudSection(
      title: 'إدارة العروض',
      fields: const [
        CrudFieldDef(key: 'name', label: 'اسم العرض', required: true),
        CrudFieldDef(key: 'promoType', label: 'نوع العرض', readItemKey: 'promo_type'),
        CrudFieldDef(key: 'status', label: 'الحالة'),
      ],
      loadItems: AdminRepository.instance.fetchPromotions,
      onCreate: (v) => AdminRepository.instance.createPromotion(
        name: v['name'] ?? '',
        promoType: (v['promoType']?.isEmpty ?? true) ? 'percentage' : v['promoType']!,
        status: (v['status']?.isEmpty ?? true) ? 'active' : v['status']!,
      ),
      onUpdate: (item, v) => AdminRepository.instance.updatePromotion(
        item['id'].toString(),
        name: v['name'],
        promoType: v['promoType'],
        status: v['status'],
      ),
      onDelete: (item) => AdminRepository.instance.deletePromotion(item['id'].toString()),
    );
  }
}
