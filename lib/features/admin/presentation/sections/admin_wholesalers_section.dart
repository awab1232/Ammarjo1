import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminWholesalersSection extends StatelessWidget {
  const AdminWholesalersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminStatusSection(
      title: 'قائمة تجار الجملة',
      loadItems: AdminRepository.instance.fetchWholesalers,
      onUpdateStatus: (item, status) =>
          AdminRepository.instance.updateWholesaler(item['id'].toString(), status: status),
    );
  }
}
