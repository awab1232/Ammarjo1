import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/session/backend_identity_controller.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';
import '../../data/audit_repository.dart';
import '../../data/backend_admin_client.dart';

/// إدارة مستخدمي الخادم (PostgreSQL) عبر `/admin/rest/users`.
class AdminUsersSection extends StatefulWidget {
  const AdminUsersSection({super.key});

  @override
  State<AdminUsersSection> createState() => _AdminUsersSectionState();
}

class _AdminUsersSectionState extends State<AdminUsersSection> {
  static const int _pageSize = 20;
  final List<Map<String, dynamic>> _users = List<Map<String, dynamic>>.empty(growable: true);
  int? _nextOffset;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  String _userKey(Map<String, dynamic> row) {
    return (row['firebase_uid'] as String?)?.trim().isNotEmpty == true
        ? (row['firebase_uid'] as String).trim()
        : (row['id']?.toString() ?? '');
  }

  Future<void> _loadInitial() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _users.clear();
      _nextOffset = null;
      _hasMore = true;
    });
    try {
      final result = await BackendAdminClient.instance.fetchUsers(limit: _pageSize, offset: 0);
      if (!mounted) return;
      final items = result?['items'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _users.addAll(list);
        _nextOffset = (result?['nextOffset'] as num?)?.toInt();
        _hasMore = _nextOffset != null;
      });
    } on Object {
      debugPrint('❌ Error loading users');
      if (!mounted) return;
      setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _nextOffset == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final off = _nextOffset!;
      final result = await BackendAdminClient.instance.fetchUsers(limit: _pageSize, offset: off);
      if (!mounted) return;
      final items = result?['items'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _users.addAll(list);
        _nextOffset = (result?['nextOffset'] as num?)?.toInt();
        _hasMore = _nextOffset != null;
      });
    } on Object {
      debugPrint('❌ Error loading more users');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _changeUserRole({
    required BuildContext context,
    required String userPatchId,
    required String targetEmail,
    required Map<String, dynamic> userData,
  }) async {
    final actorUid = UserSession.currentUid;
    if (actorUid.isEmpty) return;
    final actorEmail = UserSession.currentEmail;

    final oldRoleStr =
        PermissionService.staffRoleFromUserData(userData) ?? (userData['role'] as String? ?? '');
    String selected = PermissionService.normalizeRole(userData['role'] as String?) ??
        PermissionService.staffRoleFromUserData(userData) ??
        PermissionService.roleCustomer;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('تغيير الدور', style: GoogleFonts.tajawal()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الدور الجديد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selected,
                    items: [
                      PermissionService.roleAdmin,
                      PermissionService.roleStoreOwner,
                      PermissionService.roleTechnician,
                      PermissionService.roleCustomer,
                      PermissionService.roleSystemInternal,
                    ]
                        .map(
                          (r) => DropdownMenuItem<String>(
                            value: r,
                            child: Text(r, style: GoogleFonts.tajawal()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => selected = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !context.mounted) return;

    try {
      await AdminRepository.instance.setUserStaffRole(uid: userPatchId, newRole: selected);
      await AuditRepository.logAction(
        userId: actorUid,
        userEmail: actorEmail,
        action: 'user.role_change',
        targetType: 'user',
        targetId: userPatchId,
        details: {
          'oldRole': oldRoleStr,
          'newRole': selected,
          'targetUserEmail': targetEmail,
          'changedBy': actorEmail,
        },
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تغيير دور المستخدم بنجاح', style: GoogleFonts.tajawal())),
        );
      }
      await _loadInitial();
    } on Object {
      debugPrint('[AdminUsersSection] setUserStaffRole failed');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تغيير الدور', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BackendIdentityController.instance,
      builder: (context, _) {
        final me = BackendIdentityController.instance.me;
        final meData = me == null ? null : <String, dynamic>{'role': me.role, 'email': me.email};
        final myRole = PermissionService.staffRoleFromUserData(meData);
        final canChangeRoles = myRole == PermissionService.roleAdmin || myRole == PermissionService.roleSystemInternal;
        final currentUid = UserSession.currentUid;

        if (_hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('تعذر تحميل البيانات'),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _loadInitial, child: const Text('إعادة المحاولة')),
              ],
            ),
          );
        }
        if (_isLoading && _users.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final docs = _users;
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد بيانات مستخدمين في هذه الصفحة.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadInitial,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text('تحديث القائمة', style: GoogleFonts.tajawal()),
                  ),
                ],
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _loadInitial,
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                if (_hasMore && !_isLoadingMore) _loadMore();
              }
              return false;
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final x = docs[i];
                      final patchId = x['id']?.toString() ?? x['firebase_uid']?.toString() ?? '';
                      final rowKey = _userKey(x);
                      final email = (x['email'] as String?) ?? '';
                      final wallet = (x['wallet_balance'] as num?)?.toDouble() ?? 0;
                      final banned = x['banned'] == true;
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 1,
                        child: ListTile(
                          title: Text(email.isEmpty ? rowKey : email, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            'محفظة: ${wallet.toStringAsFixed(3)} JD${banned ? ' · محظور' : ''}',
                            style: GoogleFonts.tajawal(fontSize: 12, color: banned ? Colors.red : AppColors.textSecondary),
                          ),
                          isThreeLine: false,
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              if (canChangeRoles && currentUid.isNotEmpty && rowKey != currentUid && patchId.isNotEmpty)
                                TextButton(
                                  onPressed: () => _changeUserRole(
                                    context: context,
                                    userPatchId: patchId,
                                    targetEmail: email,
                                    userData: x,
                                  ),
                                  child: Text('تغيير الدور', style: GoogleFonts.tajawal(color: AppColors.navy)),
                                ),
                              if (!banned && patchId.isNotEmpty)
                                TextButton(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('حظر المستخدم؟', style: GoogleFonts.tajawal()),
                                        content: Text(
                                          'لن يتمكن من استخدام التطبيق بعد تسجيل الدخول التالي.',
                                          style: GoogleFonts.tajawal(fontSize: 14),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('حظر'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true && context.mounted) {
                                      try {
                                        await AdminRepository.instance.setUserBanned(patchId, true);
                                        final actorUid = UserSession.currentUid;
                                        if (actorUid.isNotEmpty) {
                                          await AuditRepository.logAction(
                                            userId: actorUid,
                                            userEmail: UserSession.currentEmail,
                                            action: 'user.ban',
                                            targetType: 'user',
                                            targetId: patchId,
                                            details: {'banned': true},
                                          );
                                        }
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('تم الحظر', style: GoogleFonts.tajawal())),
                                          );
                                        }
                                        await _loadInitial();
                                      } on Object {
                                        debugPrint('[AdminUsersSection] ban user failed');
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('فشل الحظر', style: GoogleFonts.tajawal())),
                                          );
                                        }
                                      }
                                    }
                                  },
                                  child: Text('حظر', style: GoogleFonts.tajawal(color: Colors.orange)),
                                )
                              else if (patchId.isNotEmpty)
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      await AdminRepository.instance.setUserBanned(patchId, false);
                                      final actorUid = UserSession.currentUid;
                                      if (actorUid.isNotEmpty) {
                                        await AuditRepository.logAction(
                                          userId: actorUid,
                                          userEmail: UserSession.currentEmail,
                                          action: 'user.unban',
                                          targetType: 'user',
                                          targetId: patchId,
                                          details: {'banned': false},
                                        );
                                      }
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('تم إلغاء الحظر', style: GoogleFonts.tajawal())),
                                        );
                                      }
                                      await _loadInitial();
                                    } on Object {
                                      debugPrint('[AdminUsersSection] unban user failed');
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('فشل إلغاء الحظر', style: GoogleFonts.tajawal())),
                                        );
                                      }
                                    }
                                  },
                                  child: Text('إلغاء الحظر', style: GoogleFonts.tajawal(color: Colors.green)),
                                ),
                              if (patchId.isNotEmpty)
                                TextButton(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('حذف المستخدم من الخادم؟', style: GoogleFonts.tajawal()),
                                        content: Text(
                                          'يُحذف السجل من قاعدة بيانات الطلبات. لا يُلغى حساب Firebase من هنا.',
                                          style: GoogleFonts.tajawal(fontSize: 13),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true && context.mounted) {
                                      await AdminRepository.instance.deleteUserDocument(patchId);
                                      final actorUid = UserSession.currentUid;
                                      if (actorUid.isNotEmpty) {
                                        await AuditRepository.logAction(
                                          userId: actorUid,
                                          userEmail: UserSession.currentEmail,
                                          action: 'user.delete_document',
                                          targetType: 'user',
                                          targetId: patchId,
                                        );
                                      }
                                      await _loadInitial();
                                    }
                                  },
                                  child: Text('حذف', style: GoogleFonts.tajawal(color: Colors.red)),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_hasMore || _isLoadingMore)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _isLoadingMore
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(color: AppColors.orange),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
