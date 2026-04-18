import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/firebase/user_notifications_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/admin_list_widgets.dart';
import '../../data/backend_admin_client.dart';

/// طلبات المتاجر والمتاجر المعتمدة — من `/admin/rest/stores`.
class AdminStoreRequestsSection extends StatelessWidget {
  const AdminStoreRequestsSection({super.key, this.categoryFilter});

  final String? categoryFilter;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            labelColor: const Color(0xFFFF6B00),
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: const Color(0xFFFF6B00),
            tabs: [
              Tab(child: Text('طلبات معلقة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
              Tab(child: Text('متاجر معتمدة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PendingTab(categoryFilter: categoryFilter),
                _ApprovedTab(categoryFilter: categoryFilter),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<FeatureState<List<Map<String, dynamic>>>> _loadAllStores() async {
  final out = <Map<String, dynamic>>[];
  var off = 0;
  for (var k = 0; k < 50; k++) {
    final r = await BackendAdminClient.instance.fetchStores(limit: 100, offset: off);
    if (r == null) {
      return FeatureState.failure('Failed to load stores from backend.');
    }
    final items = r['items'];
    if (items is List) {
      for (final e in items) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
    }
    final next = (r['nextOffset'] as num?)?.toInt();
    if (next == null) break;
    off = next;
  }
  return FeatureState.success(out);
}

class _PendingTab extends StatefulWidget {
  const _PendingTab({this.categoryFilter});
  final String? categoryFilter;

  @override
  State<_PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends State<_PendingTab> {
  Future<FeatureState<List<Map<String, dynamic>>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = _loadAllStores());

  Future<String?> _askRejectionReason(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سبب الرفض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          style: GoogleFonts.tajawal(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('تأكيد', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (!Firebase.apps.isNotEmpty) {
      return Center(child: Text('Firebase غير جاهز', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
    }
    return FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const AdminListShimmer();
        if (snap.data case FeatureFailure(:final message)) {
          return Center(child: Text(message, style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
        }
        final state = snap.data!;
        if (state is! FeatureSuccess<List<Map<String, dynamic>>>) {
          return AdminErrorRetryBody(onRetry: _reload);
        }
        final cf = widget.categoryFilter?.trim();
        var list = state.data.where((m) => (m['status']?.toString() ?? '') == 'pending').toList();
        if (cf != null && cf.isNotEmpty) {
          list = list.where((m) => (m['category']?.toString() ?? '') == cf).toList();
        }
        if (list.isEmpty) {
          return Center(child: Text('لا طلبات معلقة', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final m = list[i];
              final id = m['id']?.toString() ?? '';
              final name = m['name']?.toString() ?? '—';
              final owner = m['owner_id']?.toString() ?? '';
              final cat = m['category']?.toString() ?? '—';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 16)),
                      Text('المعرّف: $id', style: GoogleFonts.tajawal(fontSize: 12)),
                      Text('المالك: $owner', style: GoogleFonts.tajawal(fontSize: 13)),
                      Text('التصنيف: $cat', style: GoogleFonts.tajawal(fontSize: 13)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () async {
                                    final reason = await _askRejectionReason(context);
                                    if (reason == null || reason.trim().isEmpty) return;
                                    final res = await BackendAdminClient.instance.updateStoreStatus(id, 'rejected');
                                    if (res == null) return;
                                    if (owner.isNotEmpty) {
                                      try {
                                        await UserNotificationsRepository.sendNotificationToUser(
                                          userId: owner,
                                          title: 'تم رفض طلب المتجر',
                                          body: reason.trim(),
                                          type: 'store_request_rejected',
                                          referenceId: id,
                                        );
                                      } on Object {
                                        debugPrint('[AdminStoreRequests] reject notify failed');
                                      }
                                    }
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('تم الرفض', style: GoogleFonts.tajawal())),
                                      );
                                      _reload();
                                    }
                                  },
                            icon: const Icon(Icons.close_rounded, color: AppColors.error, size: 20),
                            label: Text('رفض', style: GoogleFonts.tajawal(color: AppColors.error)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () async {
                                    final res = await BackendAdminClient.instance.updateStoreStatus(id, 'approved');
                                    if (res == null) return;
                                    if (owner.isNotEmpty) {
                                      try {
                                        await UserNotificationsRepository.sendNotificationToUser(
                                          userId: owner,
                                          title: 'تم قبول متجرك',
                                          body: 'يمكنك الآن إدارة $name من التطبيق.',
                                          type: 'store_request_approved',
                                          referenceId: id,
                                        );
                                      } on Object {
                                        debugPrint('[AdminStoreRequests] approve notify failed');
                                      }
                                    }
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('تم القبول', style: GoogleFonts.tajawal())),
                                      );
                                      _reload();
                                    }
                                  },
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: Text('قبول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ApprovedTab extends StatefulWidget {
  const _ApprovedTab({this.categoryFilter});
  final String? categoryFilter;

  @override
  State<_ApprovedTab> createState() => _ApprovedTabState();
}

class _ApprovedTabState extends State<_ApprovedTab> {
  Future<FeatureState<List<Map<String, dynamic>>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = _loadAllStores());

  @override
  Widget build(BuildContext context) {
    if (!Firebase.apps.isNotEmpty) {
      return Center(child: Text('Firebase غير جاهز', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
    }
    return FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const AdminListShimmer();
        if (snap.data case FeatureFailure(:final message)) {
          return Center(child: Text(message, style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
        }
        final state = snap.data!;
        if (state is! FeatureSuccess<List<Map<String, dynamic>>>) {
          return AdminErrorRetryBody(onRetry: _reload);
        }
        final cf = widget.categoryFilter?.trim();
        var list = state.data.where((m) => (m['status']?.toString() ?? '') == 'approved').toList();
        if (cf != null && cf.isNotEmpty) {
          list = list.where((m) => (m['category']?.toString() ?? '') == cf).toList();
        }
        if (list.isEmpty) {
          return Center(child: Text('لا متاجر معتمدة', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final m = list[i];
              final name = m['name']?.toString() ?? '—';
              final owner = m['owner_id']?.toString() ?? '';
                return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    'المالك: $owner\nلضبط نسبة العمولة: لوحة الإدارة ← العمولات.',
                    style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('حذف المتجر من قاعدة البيانات يتم من الخادم.', style: GoogleFonts.tajawal())),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
