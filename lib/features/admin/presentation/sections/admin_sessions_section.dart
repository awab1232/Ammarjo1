import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/config/backend_orders_config.dart';
import '../../../../core/theme/app_colors.dart';

/// Admin section: View and manage active user sessions (device tracking).
class AdminSessionsSection extends StatefulWidget {
  const AdminSessionsSection({super.key});

  @override
  State<AdminSessionsSection> createState() => _AdminSessionsSectionState();
}

class _AdminSessionsSectionState extends State<AdminSessionsSection> {
  List<Map<String, dynamic>> _sessions = List<Map<String, dynamic>>.empty(growable: true);
  bool _loading = false;
  String? _error;
  int _total = 0;
  int _offset = 0;
  static const int _limit = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _token() async {
    if (!UserSession.isLoggedIn) return null;
    final token = (UserSession.authToken ?? '').trim();
    if (token.isEmpty) return null;
    return token;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _token();
      if (token == null) throw Exception('not authenticated');
      final base = BackendOrdersConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/admin/rest/sessions?limit=$_limit&offset=$_offset');
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rows = body['rows'] as List? ?? const <dynamic>[];
      setState(() {
        _sessions = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _total = (body['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } on Object catch (e) {
      setState(() {
        _error = 'تعذّر التحميل: $e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteSession(String id) async {
    setState(() => _loading = true);
    try {
      final token = await _token();
      if (token == null) throw Exception('not authenticated');
      final base = BackendOrdersConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/admin/rest/sessions/$id');
      await http.delete(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } on Object {
      // ignore, will reload
    }
    await _load();
  }

  Future<void> _deleteAllForUser(String firebaseUid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تسجيل خروج من كل الأجهزة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text('سيتم حذف جميع جلسات هذا المستخدم. هل أنت متأكد؟', style: GoogleFonts.tajawal()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text('حذف الكل', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final token = await _token();
      if (token == null) throw Exception('not authenticated');
      final base = BackendOrdersConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/admin/rest/sessions/user/$firebaseUid');
      await http.delete(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    } on Object {
      // ignore
    }
    await _load();
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } on Object {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'الجلسات النشطة ($_total)',
                  style: GoogleFonts.tajawal(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),

        if (_loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: Colors.red)),
          )
        else if (_sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Text('لا توجد جلسات مسجّلة', textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _sessions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final s = _sessions[i];
              final uid = s['firebase_uid']?.toString() ?? '';
              final deviceOs = s['device_os']?.toString() ?? '?';
              final deviceName = s['device_name']?.toString() ?? '?';
              final appVersion = s['app_version']?.toString() ?? '';
              final ipAddress = s['ip_address']?.toString();
              final lastLogin = _formatDate(s['last_login_at']?.toString());

              return Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // OS icon
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          deviceOs == 'ios'
                              ? Icons.phone_iphone_rounded
                              : deviceOs == 'android'
                                  ? Icons.phone_android_rounded
                                  : deviceOs == 'web'
                                      ? Icons.web_rounded
                                      : Icons.devices_rounded,
                          color: AppColors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$deviceName ($deviceOs)',
                              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'UID: ${uid.length > 16 ? uid.substring(0, 16) : uid}…',
                              style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                            ),
                            if (appVersion.isNotEmpty)
                              Text(
                                'التطبيق: $appVersion',
                                style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            if (ipAddress != null && ipAddress.isNotEmpty)
                              Text(
                                'IP: $ipAddress',
                                style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            Text(
                              'آخر دخول: $lastLogin',
                              style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'خيارات',
                        onSelected: (action) async {
                          if (action == 'delete_session') {
                            await _deleteSession(s['id']?.toString() ?? '');
                          } else if (action == 'delete_user_sessions') {
                            await _deleteAllForUser(uid);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'delete_session',
                            child: Row(
                              children: [
                                const Icon(Icons.logout, size: 18, color: Colors.red),
                                const SizedBox(width: 8),
                                Text('إنهاء هذه الجلسة', style: GoogleFonts.tajawal()),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete_user_sessions',
                            child: Row(
                              children: [
                                const Icon(Icons.devices_other, size: 18, color: Colors.red),
                                const SizedBox(width: 8),
                                Text('تسجيل خروج من كل الأجهزة', style: GoogleFonts.tajawal()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        // Pagination
        if (_total > _limit)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _offset > 0
                      ? () {
                          setState(() => _offset = (_offset - _limit).clamp(0, _total));
                          _load();
                        }
                      : null,
                ),
                Text(
                  '${_offset + 1}–${(_offset + _sessions.length).clamp(0, _total)} من $_total',
                  style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: (_offset + _limit) < _total
                      ? () {
                          setState(() => _offset += _limit);
                          _load();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
