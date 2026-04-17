import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/admin_list_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/admin_repository.dart';
import '../../data/backend_admin_client.dart';
import '../widgets/admin_list_widgets.dart';

class AdminWalletSection extends StatefulWidget {
  const AdminWalletSection({super.key});

  @override
  State<AdminWalletSection> createState() => _AdminWalletSectionState();
}

class _AdminWalletSectionState extends State<AdminWalletSection> {
  final _searchCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _search = '';
  String? _selectedUserEmail;
  final List<Map<String, dynamic>> _users = [];
  int? _nextOffset;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _loading = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _users.clear();
      _nextOffset = null;
      _hasMore = true;
    });
    try {
      final res = await BackendAdminClient.instance.fetchUsers(limit: AdminListConstants.pageSize, offset: 0);
      final items = res?['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) _users.add(Map<String, dynamic>.from(e));
        }
      }
      _nextOffset = (res?['nextOffset'] as num?)?.toInt();
      _hasMore = _nextOffset != null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextOffset == null) return;
    setState(() => _loadingMore = true);
    try {
      final res = await BackendAdminClient.instance.fetchUsers(limit: AdminListConstants.pageSize, offset: _nextOffset!);
      final items = res?['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) _users.add(Map<String, dynamic>.from(e));
        }
      }
      _nextOffset = (res?['nextOffset'] as num?)?.toInt();
      _hasMore = _nextOffset != null;
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _adjustBalance(BuildContext context) async {
    final adminEmail = context.read<StoreController>().profile?.email.trim() ?? '';
    final userEmail = (_selectedUserEmail ?? '').trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (adminEmail.isEmpty || userEmail.isEmpty || amount == 0) return;
    await AdminRepository.instance.adjustWalletBalance(
      userEmail: userEmail,
      amountDelta: amount,
      adminEmail: adminEmail,
      note: 'Manual top-up / adjustment',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تعديل الرصيد بنجاح.', style: GoogleFonts.tajawal())),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminListShimmer();
    }

    final q = _search.trim().toLowerCase();
    var users = q.isEmpty
        ? _users
        : _users.where((x) {
            final email = ((x['email'] as String?) ?? '').toLowerCase();
            final phone = ((x['phone'] as String?) ?? '').toLowerCase();
            return email.contains(q) || phone.contains(q);
          }).toList();
    users = users.where((x) => ((x['email'] as String?) ?? '').trim().isNotEmpty).toList();

    final showLoadMore = _hasMore;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('المحفظة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'البحث يطبق على المستخدمين المحمّلين حالياً. استخدم «تحميل المزيد» إن لم يظهر المستخدم.',
          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'ابحث بالبريد أو الهاتف',
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _selectedUserEmail != null && users.any((d) => ((d['email'] as String?) ?? '') == _selectedUserEmail)
              ? _selectedUserEmail
              : null,
          items: users.map((x) {
            final email = (x['email'] as String?) ?? '';
            return DropdownMenuItem<String>(value: email, child: Text(email, style: GoogleFonts.tajawal()));
          }).toList(),
          onChanged: (v) => setState(() => _selectedUserEmail = v),
          decoration: InputDecoration(
            labelText: 'اختر المستخدم',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(
            labelText: 'تعديل الرصيد (+/-)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () => _adjustBalance(context),
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          child: Text('تنفيذ التعديل', style: GoogleFonts.tajawal(color: Colors.white)),
        ),
        if (users.isEmpty && _users.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text('لا مستخدمين في الصفحة الحالية.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('تحديث', style: GoogleFonts.tajawal()),
                ),
              ],
            ),
          ),
        ],
        if (showLoadMore || _loadingMore) ...[
          const SizedBox(height: 16),
          Center(
            child: _loadingMore
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(color: AppColors.orange),
                  )
                : TextButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text('تحميل المزيد من المستخدمين', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ],
    );
  }
}
