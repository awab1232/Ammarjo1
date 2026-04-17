import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import 'admin_rest_widgets.dart';

class AdminSupportChatsSection extends StatelessWidget {
  const AdminSupportChatsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminStatusSection(
      title: 'دعم العملاء',
      loadItems: AdminRepository.instance.fetchSupportTickets,
      onUpdateStatus: (item, status) =>
          AdminRepository.instance.updateSupportTicket(item['id'].toString(), status: status),
    );
  }
}
