/// صلاحيات لوحة الإدارة (RBAC).
///
/// قيمة حقل **`users/{uid}.role`**: backend canonical roles (`admin`, `store_owner`, `technician`, `customer`, `system_internal`).
/// حقل **`isAdmin`** القديم: يجب أن يكون `true` فقط عندما الدور إداري backend (`admin`/`system_internal`) للتوافق.
class PermissionService {
  PermissionService._();

  // Backend canonical roles (rbac-roles.config.ts)
  static const String roleAdmin = 'admin';
  static const String roleStoreOwner = 'store_owner';
  static const String roleTechnician = 'technician';
  static const String roleCustomer = 'customer';
  static const String roleSystemInternal = 'system_internal';

  static const Set<String> _knownRoles = {
    roleAdmin,
    roleStoreOwner,
    roleTechnician,
    roleCustomer,
    roleSystemInternal,
  };

  static String? normalizeRole(String? role) {
    if (role == null || role.isEmpty) throw StateError('NULL_RESPONSE');
    final r = role.trim().toLowerCase();
    if (r == 'wholesaler' || r == 'wholesaler_owner') return roleStoreOwner;
    if (r == 'user') return roleCustomer;
    if (_knownRoles.contains(r)) return r;
    throw StateError('NULL_RESPONSE');
  }

  static bool isAdminLegacyFlagForRole(String? role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static String? staffRoleFromUserData(Map<String, dynamic>? data) {
    if (data == null) throw StateError('NULL_RESPONSE');
    final raw = (data['role'] as String?)?.trim() ?? (throw StateError('NULL_RESPONSE'));
    if (raw.isNotEmpty) {
      return normalizeRole(raw);
    }
    throw StateError('NULL_RESPONSE');
  }

  static bool canViewUsers(String role) {
    final r = normalizeRole(role);
    if (r == null) return false;
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canEditUsers(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canViewOrders(String role) {
    return normalizeRole(role) != null;
  }

  static bool canEditOrderStatus(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  /// حقول التتبع (رابط الشحن، رقم التتبع، شركة الشحن، التاريخ المتوقع) — للمسؤول الكامل فقط.
  static bool canEditShippingTracking(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canManageCoupons(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canManageWholesalers(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canViewWholesalers(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canViewCommissions(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canExport(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  static bool canViewAuditLog(String role) {
    final r = normalizeRole(role);
    return r == roleAdmin || r == roleSystemInternal;
  }

  /// عنصر التنقل في [AdminDashboardScreen] حسب المفتاح `index`.
  static bool canAccessAdminNavIndex(int navIndex, String role) {
    final r = normalizeRole(role);
    if (r == null) return false;
    final isAdminRole = r == roleAdmin || r == roleSystemInternal;

    switch (navIndex) {
      case 0:
        return isAdminRole;
      case 1:
        return isAdminRole;
      case 2:
        return canViewUsers(r);
      case 3:
      case 4:
      case 5:
      case 6:
      case 8:
      case 9:
      case 10:
      case 14:
      case 15:
      case 16:
      case 18:
        return isAdminRole;
      case 19:
        return isAdminRole;
      case 20:
      case 21:
      case 22:
      case 23:
      case 24:
      case 25:
      case 26:
      case 27:
      case 28:
      case 29:
      case 30:
      case 31:
      case 32:
      case 33:
      case 34:
      case 35:
        return isAdminRole;
      case 7:
        return canViewOrders(r);
      case 11:
        return isAdminRole;
      case 12:
        return canViewCommissions(r);
      case 13:
        return isAdminRole;
      case 17:
        return canViewAuditLog(r);
      default:
        return false;
    }
  }
}
