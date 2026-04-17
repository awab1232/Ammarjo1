import 'package:flutter/material.dart';

import 'order_tracking_screen.dart';

/// طلباتي — نفس تتبع الطلبات (Firestore `users/{uid}/orders`).
class MyOrdersPage extends StatelessWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OrderTrackingScreen(appBarTitle: 'طلباتي');
  }
}
