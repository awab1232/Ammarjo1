import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';
import '../../data/backend_admin_client.dart';
import '../widgets/admin_list_widgets.dart';

/// مراجعة بلاغات السوق — من PostgreSQL عبر `/admin/rest/reports`.
class AdminReportsSection extends StatefulWidget {
  const AdminReportsSection({super.key});

  @override
  State<AdminReportsSection> createState() => _AdminReportsSectionState();
}

class _AdminReportsSectionState extends State<AdminReportsSection> {
  bool _loading = true;
  Object? _loadError;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final raw = await BackendAdminClient.instance.fetchReports();
      final items = raw?['items'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      list.sort((a, b) {
        final ta = a['created_at'];
        final tb = b['created_at'];
        final da = ta is String ? DateTime.tryParse(ta) : null;
        final db = tb is String ? DateTime.tryParse(tb) : null;
        if (da != null && db != null) return db.compareTo(da);
        return 0;
      });
      if (mounted) {
        setState(() {
          _rows = list;
          _loading = false;
        });
      }
    } on Object {
      debugPrint('[AdminReportsSection] _load failed');
      if (mounted) {
        setState(() {
          _loadError = StateError('Failed to load reports.');
          _loading = false;
        });
      }
    }
  }

  static String _formatDate(dynamic v) {
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) {
        return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
            '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      }
    }
    return '—';
  }

  Future<void> _setResolved(String id, {String? note}) async {
    await AdminRepository.instance.updateReportFields(id, {
      'status': 'resolved',
      if (note != null) 'body': note,
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B00)));
    }
    if (_loadError != null) {
      return AdminErrorRetryBody(onRetry: _load);
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text('لا بلاغات', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final d = _rows[i];
          final id = d['id']?.toString() ?? '';
          final subject = d['subject']?.toString() ?? '—';
          final body = d['body']?.toString() ?? '—';
          final status = d['status']?.toString() ?? '—';
          final reporter = d['reporter_id']?.toString().trim() ?? '—';
          final date = _formatDate(d['created_at']);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(subject, style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('المبلّغ: $reporter', style: GoogleFonts.tajawal(fontSize: 13)),
                  Text('الحالة: $status', style: GoogleFonts.tajawal(fontSize: 13)),
                  Text('النص: $body', style: GoogleFonts.tajawal(fontSize: 14), textAlign: TextAlign.right),
                  Text('التاريخ: $date', style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: id.isEmpty
                            ? null
                            : () async {
                                try {
                                  await _setResolved(id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('تم تسوية البلاغ', style: GoogleFonts.tajawal())),
                                    );
                                  }
                                } on Object {
                                  debugPrint('[AdminReportsSection] resolve failed');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'تعذر تسوية البلاغ حالياً.',
                                          style: GoogleFonts.tajawal(),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Text('تسوية', style: GoogleFonts.tajawal()),
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
  }
}
