import '../services/permission_service.dart';

/// حقول Firestore في **`users/{uid}`** المتعلقة بالوصول للوحة الإدارة.
///
/// - **`role`** (`String`): أحد القيم:
///   [PermissionService.roleAdmin]، [PermissionService.roleStoreOwner]،
///   [PermissionService.roleTechnician]، [PermissionService.roleCustomer]،
///   [PermissionService.roleSystemInternal].
/// - **`isAdmin`** (`bool`): للتوافق مع الكود والقواعد القديمة —
///   يجب أن يكون `true` **فقط** عندما `role == full_admin`
///   (انظر [UserAdminModel.isAdminCompatFromRole]).
abstract final class UserAdminModel {
  UserAdminModel._();

  static const String fieldRole = 'role';
  static const String fieldIsAdmin = 'isAdmin';

  /// قيمة `isAdmin` المتوافقة مع الحقل `role` الجديد.
  static bool isAdminCompatFromRole(String? role) =>
      PermissionService.isAdminLegacyFlagForRole(role);

  /// ملخص من خريطة وثيقة المستخدم (للقراءة فقط).
  static UserAdminRead readFromMap(Map<String, dynamic>? data) {
    final staffRole = PermissionService.staffRoleFromUserData(data);
    return UserAdminRead(
      staffRole: staffRole,
      isAdminCompat: staffRole == PermissionService.roleAdmin || staffRole == PermissionService.roleSystemInternal,
    );
  }
}

/// لقطة قراءة لحقول الصلاحية الإدارية.
class UserAdminRead {
  const UserAdminRead({
    required this.staffRole,
    required this.isAdminCompat,
  });

  /// دور الموظف في اللوحة، أو null إن لم يكن موظفاً.
  final String? staffRole;

  /// مطابق لما يجب أن يكون عليه **`isAdmin`** في Firestore (`true` لـ full_admin فقط).
  final bool isAdminCompat;

  bool get hasPanelAccess => staffRole != null;
}
