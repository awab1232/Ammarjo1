import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../features/admin/presentation/pages/admin_dashboard_screen.dart';
import '../../features/maintenance/presentation/pages/technician_dashboard_page.dart';
import '../../features/store/presentation/pages/main_navigation_page.dart';
import '../../features/store_owner/presentation/store_owner_dashboard.dart';
import '../session/backend_identity_controller.dart';
import '../services/device_session_service.dart';
import '../services/permission_service.dart';

/// يحدد الشاشة الرئيسية بعد تسجيل الدخول اعتماداً على `/auth/me` فقط (بدون مسارات احتياطية).
Future<Widget> resolveHomeForSignedInUser(User user) async {
  await BackendIdentityController.instance.refresh();
  // Best-effort device session registration (non-blocking).
  DeviceSessionService.instance.registerSession().ignore();
  final me = BackendIdentityController.instance.me;

  if (me != null) {
    final r = PermissionService.normalizeRole(me.role);
    if (r == PermissionService.roleAdmin || r == PermissionService.roleSystemInternal) {
      return const AdminDashboardScreen();
    }
    if (r == PermissionService.roleStoreOwner) {
      final sid = me.storeId?.trim() ?? '';
      if (sid.isNotEmpty) {
        return const StoreOwnerDashboard();
      }
      return const MainNavigationPage();
    }
    if (r == PermissionService.roleTechnician) {
      return const TechnicianDashboardPage();
    }
    return const MainNavigationPage();
  }

  return const MainNavigationPage();
}
