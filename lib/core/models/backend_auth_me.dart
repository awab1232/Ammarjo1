/// Response shape for `GET /auth/me` (NestJS RBAC source of truth).
class BackendAuthMe {
  BackendAuthMe({
    required this.userId,
    required this.firebaseUid,
    required this.email,
    required this.role,
    required this.tenantId,
    required this.storeId,
    required this.storeType,
    required this.wholesalerId,
    required this.permissions,
  });

  final String? userId;
  final String firebaseUid;
  final String? email;
  final String role;
  final String? tenantId;
  final String? storeId;
  /// e.g. `construction_store`, `home_store`, `wholesale_store`
  final String? storeType;
  final String? wholesalerId;
  final List<String> permissions;

  static String _normalizeRole(Object? raw) {
    final role = raw?.toString().trim().toLowerCase() ?? '';
    if (role == 'wholesaler' || role == 'wholesaler_owner') return 'store_owner';
    if (role == 'user') return 'customer';
    if (role.isEmpty) return 'customer';
    return role;
  }

  factory BackendAuthMe.fromJson(Map<String, dynamic> j) {
    final perms = j['permissions'];
    final idFromServer = j['id']?.toString().trim();
    final legacyUserId = j['userId'] as String?;
    return BackendAuthMe(
      userId: (idFromServer != null && idFromServer.isNotEmpty) ? idFromServer : legacyUserId,
      firebaseUid: (j['firebaseUid'] as String?)?.trim() ?? '',
      email: j['email'] as String?,
      role: _normalizeRole(j['role']),
      tenantId: j['tenantId'] as String?,
      storeId: j['storeId'] as String?,
      storeType: j['storeType'] as String?,
      wholesalerId: j['wholesalerId'] as String?,
      permissions: perms is List
          ? perms.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
          : const <String>[],
    );
  }
}
