import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/admin_list_constants.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/audit_repository.dart';
import '../../data/models/audit_log_model.dart';
import '../widgets/admin_list_widgets.dart';

/// سجل التدقيق من `/admin/rest/audit-logs`.
class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  int _retryTick = 0;
  final List<Map<String, dynamic>> _rows = [];
  int _offset = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;

  String? _actionFilter;

  static const _filterChoices = <({String? key, String labelAr})>[
    (key: null, labelAr: 'كل الإجراءات'),
    (key: 'user.ban', labelAr: 'حظر مستخدم'),
    (key: 'user.unban', labelAr: 'إلغاء حظر'),
    (key: 'user.delete_document', labelAr: 'حذف وثيقة مستخدم'),
    (key: 'product.delete', labelAr: 'حذف منتج'),
    (key: 'order.status_change', labelAr: 'تغيير حالة طلب'),
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _rows.clear();
      _offset = 0;
      _hasMore = true;
      _retryTick++;
    });
    await _loadMore(first: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore({bool first = false}) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final pageState = await AuditRepository.fetchAuditLogsPage(
        limit: AdminListConstants.pageSize,
        offset: first ? 0 : _offset,
      );
      if (pageState is! FeatureSuccess<List<Map<String, dynamic>>>) return;
      final page = pageState.data;
      if (!mounted) return;
      setState(() {
        _rows.addAll(page);
        _offset = _rows.length;
        _hasMore = page.length >= AdminListConstants.pageSize;
      });
    } on Object {
      debugPrint('[AdminAuditLogScreen] load failed');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onFilterChanged(String? newKey) {
    setState(() {
      _actionFilter = newKey;
    });
    _refresh();
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '—';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildLogTile(Map<String, dynamic> row) {
    try {
      final m = AuditLogModel.fromPgRow(row);
      final target = '${m.targetType}:${m.targetId}';
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      m.userEmail.isNotEmpty ? m.userEmail : m.userId,
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  Text(
                    _formatTime(m.timestamp),
                    style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(m.action, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.orange)),
              const SizedBox(height: 4),
              Text(target, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
              if (m.details.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    m.details.toString(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tajawal(fontSize: 11, color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
      );
    } on Object {
      debugPrint('[AdminAuditLogScreen] parse failed');
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayRows = _actionFilter == null
        ? _rows
        : _rows.where((e) => e['action']?.toString() == _actionFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DropdownButtonFormField<String?>(
            value: _actionFilter,
            decoration: InputDecoration(
              labelText: 'فلتر حسب الإجراء',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
            items: _filterChoices
                .map(
                  (e) => DropdownMenuItem<String?>(
                    value: e.key,
                    child: Text(e.labelAr, style: GoogleFonts.tajawal(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: _onFilterChanged,
          ),
        ),
        Expanded(
          child: _loading
              ? const AdminListShimmer()
              : KeyedSubtree(
                  key: ValueKey<int>(_retryTick),
                  child: displayRows.isEmpty
                      ? Center(child: Text('لا سجلات.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: displayRows.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i >= displayRows.length) {
                              return TextButton.icon(
                                onPressed: _loadingMore ? null : () => _loadMore(),
                                icon: const Icon(Icons.expand_more),
                                label: Text('تحميل المزيد', style: GoogleFonts.tajawal()),
                              );
                            }
                            return _buildLogTile(displayRows[i]);
                          },
                        ),
                ),
        ),
      ],
    );
  }
}
