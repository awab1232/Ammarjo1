import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/backend_admin_client.dart';
import '../../../../core/theme/app_colors.dart';

/// طلبات تسجيل السائقين — `GET /admin/rest/driver-requests` + قبول / رفض.
class AdminDriverRequestsPage extends StatefulWidget {
  const AdminDriverRequestsPage({super.key});

  @override
  State<AdminDriverRequestsPage> createState() => _AdminDriverRequestsPageState();
}

class _AdminDriverRequestsPageState extends State<AdminDriverRequestsPage> {
  Timer? _timer;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = List<Map<String, dynamic>>.empty(growable: true);
  String? _busyId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => unawaited(_load(silent: true)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final body = await BackendAdminClient.instance.fetchDriverRequests();
      final items = body?['items'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      if (mounted) {
        setState(() {
          _rows = list;
          _loading = false;
          _error = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر تحميل الطلبات';
        });
      }
    }
  }

  Future<void> _approve(String id) async {
    setState(() => _busyId = id);
    try {
      await BackendAdminClient.instance.approveDriverRequest(id);
      await _load(silent: true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر القبول', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(String id) async {
    setState(() => _busyId = id);
    try {
      await BackendAdminClient.instance.rejectDriverRequest(id);
      await _load(silent: true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الرفض', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  String _statusAr(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'pending':
        return 'قيد المراجعة';
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return s ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'طلبات السائقين',
                    style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : () => _load(silent: false),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Text(
              user?.email ?? '',
              style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: GoogleFonts.tajawal(color: Colors.red.shade800))
            else if (_loading && _rows.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: _rows.isEmpty
                    ? Center(child: Text('لا توجد طلبات', style: GoogleFonts.tajawal()))
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final r = _rows[i];
                          final id = r['id']?.toString() ?? '';
                          final name = r['full_name']?.toString() ?? '—';
                          final phone = r['phone']?.toString() ?? '—';
                          final img = r['identity_image_url']?.toString() ?? '';
                          final st = r['status']?.toString() ?? '';
                          final pending = st.toLowerCase() == 'pending';
                          return Card(
                            elevation: 0,
                            color: AppColors.surfaceSecondary,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (img.isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            img,
                                            width: 72,
                                            height: 72,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, err, st) => const Icon(Icons.broken_image_outlined),
                                          ),
                                        )
                                      else
                                        const Icon(Icons.image_not_supported_outlined, size: 48),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                            const SizedBox(height: 4),
                                            Text(phone, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                                            const SizedBox(height: 4),
                                            Text(
                                              'الحالة: ${_statusAr(st)}',
                                              style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.orange),
                                            ),
                                            Text(
                                              'uid: ${r['auth_uid'] ?? '—'}',
                                              style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (pending) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: _busyId != null ? null : () => _approve(id),
                                            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                                            child: _busyId == id
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : Text('قبول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _busyId != null ? null : () => _reject(id),
                                            child: _busyId == id
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  )
                                                : Text('رفض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
