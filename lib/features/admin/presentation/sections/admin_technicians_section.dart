import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../widgets/admin_list_widgets.dart';
import '../../data/admin_repository.dart';
import '../../data/backend_admin_client.dart';

/// طلبات الانضمام + ملفات الفنيين — PostgreSQL عبر REST.
class AdminTechniciansSection extends StatefulWidget {
  const AdminTechniciansSection({super.key});

  @override
  State<AdminTechniciansSection> createState() => _AdminTechniciansSectionState();
}

class _AdminTechniciansSectionState extends State<AdminTechniciansSection> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _techSearch = '';
  int _profilesTick = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _normTech(Map<String, dynamic> m) {
    final specs = m['specialties'];
    return <String, dynamic>{
      ...m,
      'displayName': m['display_name'] ?? m['displayName'] ?? 'فني',
      'specialties': specs is List ? specs : <String>[],
    };
  }

  Future<void> _editTechnician(BuildContext context, String id, Map<String, dynamic> data) async {
    final d = _normTech(data);
    final nameCtrl = TextEditingController(text: d['displayName']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: d['phone']?.toString() ?? '');
    final cityCtrl = TextEditingController(text: d['city']?.toString() ?? '');
    final specCtrl = TextEditingController(
      text: (d['specialties'] is List) ? (d['specialties'] as List).map((e) => e.toString()).join(', ') : '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل فني', style: GoogleFonts.tajawal()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'الاسم')),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'الهاتف')),
              TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'المدينة')),
              TextField(
                controller: specCtrl,
                decoration: const InputDecoration(labelText: 'تخصصات (مفصولة بفواصل)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final specs = specCtrl.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final patch = <String, dynamic>{
                'displayName': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'city': cityCtrl.text.trim(),
                'specialties': specs,
              };
              try {
                await AdminRepository.instance.updateTechnicianProfile(id, patch);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  setState(() => _profilesTick++);
                }
              } on Object {
                debugPrint('[AdminTechniciansSection] save failed');
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<FeatureState<List<Map<String, dynamic>>>> _loadTechs() async {
    final raw = await BackendAdminClient.instance.fetchTechnicians();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('Invalid technicians payload.');
    final out = <Map<String, dynamic>>[];
    for (final e in items) {
      if (e is Map) out.add(_normTech(Map<String, dynamic>.from(e)));
    }
    return FeatureState.success(out);
  }

  bool _matches(Map<String, dynamic> data) {
    final q = _techSearch.trim().toLowerCase();
    if (q.isEmpty) return true;
    final name = (data['displayName'] ?? '').toString().toLowerCase();
    final specs = (data['specialties'] is List) ? (data['specialties'] as List).join(' ').toLowerCase() : '';
    final cat = (data['category'] ?? '').toString().toLowerCase();
    final city = (data['city'] ?? '').toString().toLowerCase();
    return name.contains(q) || specs.contains(q) || cat.contains(q) || city.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (val) => setState(() => _techSearch = val),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'بحث…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.orange,
            tabs: [
              Tab(child: Text('طلبات الانضمام', style: GoogleFonts.tajawal())),
              Tab(child: Text('ملفات الفنيين', style: GoogleFonts.tajawal())),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _JoinTab(onEdit: _editTechnician),
              FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
                key: ValueKey<int>(_profilesTick),
                future: _loadTechs(),
                builder: (context, snap) {
                  if (!snap.hasData) return const AdminListShimmer();
                  final rows = switch (snap.data) {
                    FeatureSuccess(:final data) => data,
                    _ => <Map<String, dynamic>>[],
                  };
                  final filtered = rows.where(_matches).toList()
                    ..sort(
                      (a, b) => (a['displayName'] ?? '')
                          .toString()
                          .compareTo((b['displayName'] ?? '').toString()),
                    );
                  if (filtered.isEmpty) {
                    return Center(child: Text('لا نتائج', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final data = filtered[i];
                      final id = data['id']?.toString() ?? '';
                      final status = (data['status']?.toString() ?? '').toLowerCase();
                      final photo = data['photoUrl']?.toString().trim() ?? '';
                      final specs = data['specialties'];
                      final specStr = specs is List ? specs.map((e) => e.toString()).join('، ') : '';
                      Color chipColor = AppColors.textSecondary;
                      if (status == 'pending') chipColor = Colors.orange;
                      if (status == 'rejected') chipColor = Colors.red;
                      if (status == 'approved') chipColor = Colors.green;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: AppColors.border,
                                backgroundImage: photo.isNotEmpty ? NetworkImage(webSafeImageUrl(photo)) : null,
                                child: photo.isEmpty ? Icon(Icons.person_rounded, color: AppColors.textSecondary, size: 32) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            data['displayName']?.toString() ?? 'فني',
                                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                        Chip(
                                          label: Text(status, style: GoogleFonts.tajawal(fontSize: 11, color: Colors.white)),
                                          backgroundColor: chipColor,
                                        ),
                                      ],
                                    ),
                                    if (specStr.isNotEmpty)
                                      Text('تخصص: $specStr', style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary), textAlign: TextAlign.right),
                                    Text(
                                      data['email']?.toString() ?? '',
                                      style: GoogleFonts.tajawal(fontSize: 11),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 8,
                                      children: [
                                        if (status == 'pending') ...[
                                          FilledButton(
                                            onPressed: () async {
                                              try {
                                                await AdminRepository.instance.setTechnicianStatus(id, 'approved');
                                                setState(() => _profilesTick++);
                                              } on Object {
                                                debugPrint('[AdminTechniciansSection] approve failed');
                                              }
                                            },
                                            style: FilledButton.styleFrom(backgroundColor: Colors.green),
                                            child: Text('موافقة', style: GoogleFonts.tajawal(color: Colors.white)),
                                          ),
                                          FilledButton(
                                            onPressed: () async {
                                              try {
                                                await AdminRepository.instance.setTechnicianStatus(id, 'rejected');
                                                setState(() => _profilesTick++);
                                              } on Object {
                                                debugPrint('[AdminTechniciansSection] reject failed');
                                              }
                                            },
                                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                            child: Text('رفض', style: GoogleFonts.tajawal(color: Colors.white)),
                                          ),
                                        ],
                                        OutlinedButton(
                                          onPressed: () => _editTechnician(context, id, data),
                                          child: Text('تعديل', style: GoogleFonts.tajawal()),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JoinTab extends StatefulWidget {
  const _JoinTab({required this.onEdit});
  final Future<void> Function(BuildContext context, String id, Map<String, dynamic> data) onEdit;

  @override
  State<_JoinTab> createState() => _JoinTabState();
}

class _JoinTabState extends State<_JoinTab> {
  Future<FeatureState<List<TechnicianJoinRequest>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => setState(() => _future = AdminRepository.instance.fetchPendingTechnicianJoinRequests());

  Future<String?> _askReason(BuildContext context) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سبب الرفض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: TextField(controller: ctrl, minLines: 2, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.tajawal())),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('تأكيد', style: GoogleFonts.tajawal())),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeatureState<List<TechnicianJoinRequest>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return AdminErrorRetryBody(onRetry: _reload);
        }
        if (!snap.hasData) return const AdminListShimmer();
        final state = snap.data!;
        if (state is! FeatureSuccess<List<TechnicianJoinRequest>>) {
          return AdminErrorRetryBody(onRetry: _reload);
        }
        final requests = state.data;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('طلبات معلّقة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (requests.isEmpty)
                Text('لا توجد طلبات.', style: GoogleFonts.tajawal(color: AppColors.textSecondary))
              else
                ...requests.map((r) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(r.displayName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                          Text(r.email, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
                          Text('الفئة: ${r.categoryId}', style: GoogleFonts.tajawal(fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    try {
                                      final result = await AdminRepository.instance.approveTechnicianRequest(
                                        r,
                                        reviewedBy: UserSession.currentUid.isNotEmpty ? UserSession.currentUid : null,
                                      );
                                      if (result is FeatureFailure<void>) return;
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('تمت الموافقة', style: GoogleFonts.tajawal()), backgroundColor: Colors.green),
                                        );
                                        _reload();
                                      }
                                    } on Object {
                                      debugPrint('[JoinTab] approve failed');
                                    }
                                  },
                                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                                  child: Text('موافقة', style: GoogleFonts.tajawal(color: Colors.white)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    final reason = await _askReason(context);
                                    if (reason == null || reason.trim().isEmpty) return;
                                    try {
                                      final result = await AdminRepository.instance.rejectTechnicianRequest(
                                        r,
                                        reviewedBy: UserSession.currentUid.isNotEmpty ? UserSession.currentUid : '',
                                        rejectionReason: reason,
                                      );
                                      if (result is FeatureFailure<void>) return;
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الرفض', style: GoogleFonts.tajawal())));
                                        _reload();
                                      }
                                    } on Object {
                                      debugPrint('[JoinTab] reject failed');
                                    }
                                  },
                                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                                  child: Text('رفض', style: GoogleFonts.tajawal(color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
