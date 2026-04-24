import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/admin_list_constants.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_notification_repository.dart';
import '../../data/models/admin_notification_model.dart';
import '../widgets/admin_list_widgets.dart';

/// إشعارات المستخدم الحالي من PostgreSQL (`GET /notifications`).
class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key, required this.adminRole});

  final String adminRole;

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  int _retryTick = 0;
  int _offset = 0;
  final List<AdminNotification> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  Future<void> _load({bool first = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (first) {
        _items.clear();
        _offset = 0;
        _hasMore = true;
      }
    });
    try {
      final batchState = await AdminNotificationRepository.fetchNotifications(
        limit: AdminListConstants.pageSize,
        offset: first ? 0 : _offset,
      );
      if (batchState is! FeatureSuccess<List<AdminNotification>>) return;
      final batch = batchState.data;
      if (!mounted) return;
      setState(() {
        if (first) {
          _items.addAll(batch);
        } else {
          _items.addAll(batch);
        }
        _offset = _items.length;
        _hasMore = batch.length >= AdminListConstants.pageSize;
      });
    } on Object {
      debugPrint('AdminNotificationsScreen _load failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final batchState = await AdminNotificationRepository.fetchNotifications(
        limit: AdminListConstants.pageSize,
        offset: _offset,
      );
      if (batchState is! FeatureSuccess<List<AdminNotification>>) return;
      final batch = batchState.data;
      if (!mounted) return;
      setState(() {
        _items.addAll(batch);
        _offset = _items.length;
        _hasMore = batch.length >= AdminListConstants.pageSize;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _onTapNotification(AdminNotification n) async {
    try {
      if (!n.isRead) {
        await AdminNotificationRepository.markAsRead(n.id);
      }
    } on Object {
      debugPrint('AdminNotificationsScreen _onTapNotification failed');
    }
    if (!mounted) return;
    setState(() => _retryTick++);
  }

  Future<void> _markAllRead() async {
    try {
      final state = await AdminNotificationRepository.markAllAsRead();
      if (state is! FeatureSuccess<void>) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تحديد الكل كمقروء حالياً.', style: GoogleFonts.tajawal())),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _retryTick++;
          _items.clear();
          _offset = 0;
          _hasMore = true;
        });
      }
      await _load(first: true);
    } on Object {
      debugPrint('AdminNotificationsScreen _markAllRead failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديد الكل كمقروء حالياً.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '—';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.adminRole.trim();
    if (role.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('الإشعارات', style: GoogleFonts.tajawal())),
        body: Center(child: Text('دور غير معروف', style: GoogleFonts.tajawal())),
      );
    }

    if (_loading && _items.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('إشعارات الإدارة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        ),
        body: const AdminListShimmer(),
      );
    }

    return Scaffold(
      key: ValueKey<int>(_retryTick),
      appBar: AppBar(
        title: Text('إشعارات الإدارة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: Text('تحديد الكل كمقروء', style: GoogleFonts.tajawal(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: _items.isEmpty
          ? Center(child: Text('لا إشعارات بعد.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)))
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final n = _items[i];
                      final unread = !n.isRead;
                      return Material(
                        color: unread ? Colors.blue.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        elevation: unread ? 0 : 1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _onTapNotification(n),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (unread)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8, top: 4),
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              n.message,
                                              style: GoogleFonts.tajawal(
                                                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _formatTime(n.createdAt),
                                            style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        n.type,
                                        style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.orange),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_hasMore || _loadingMore)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _loadingMore
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(color: AppColors.orange),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: Text('تحميل المزيد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                          ),
                  ),
              ],
            ),
    );
  }
}
