import 'package:flutter/material.dart';
import '../../../store_owner/presentation/store_owner_dashboard.dart';

class WholesalerDashboard extends StatefulWidget {
  const WholesalerDashboard({super.key});

  @override
  State<WholesalerDashboard> createState() => _WholesalerDashboardState();
}

class _WholesalerDashboardState extends State<WholesalerDashboard> {
  @override
  Widget build(BuildContext context) {
    // Unified dashboard entry-point: wholesale owners use StoreOwnerDashboard.
    return const StoreOwnerDashboard();
  }
}
