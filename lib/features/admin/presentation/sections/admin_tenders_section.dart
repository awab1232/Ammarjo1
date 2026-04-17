import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminTendersSection extends StatelessWidget {
  const AdminTendersSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminStatusSection(
      title: 'إدارة المناقصات',
      loadItems: AdminRepository.instance.fetchTenders,
      onUpdateStatus: (item, status) => AdminRepository.instance.updateTender(item['id'].toString(), status: status),
    );
  }
}
