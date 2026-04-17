import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/contracts/feature_unit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';

class AdminBoostRequestsSection extends StatefulWidget {
  const AdminBoostRequestsSection({super.key});

  @override
  State<AdminBoostRequestsSection> createState() => _AdminBoostRequestsSectionState();
}

class _AdminBoostRequestsSectionState extends State<AdminBoostRequestsSection> {
  String _statusFilter = 'pending';
  Future<FeatureState<List<Map<String, dynamic>>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = AdminRepository.instance.fetchBoostRequests(status: _statusFilter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pending', label: Text('Pending')),
                    ButtonSegment(value: 'approved', label: Text('Approved')),
                    ButtonSegment(value: 'rejected', label: Text('Rejected')),
                    ButtonSegment(value: 'all', label: Text('All')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (next) {
                    if (next.isEmpty) return;
                    _statusFilter = next.first;
                    _reload();
                  },
                  showSelectedIcon: false,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.orange));
              }
              final state = snap.data!;
              if (state is FeatureFailure<List<Map<String, dynamic>>>) {
                return Center(child: Text(state.message, style: GoogleFonts.tajawal()));
              }
              if (state is! FeatureSuccess<List<Map<String, dynamic>>>) {
                return Center(child: Text('تعذر التحميل', style: GoogleFonts.tajawal()));
              }
              final rows = state.data;
              if (rows.isEmpty) {
                return Center(child: Text('لا توجد طلبات', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final id = row['id']?.toString() ?? '';
                    final storeName = row['storeName']?.toString() ?? (row['storeId']?.toString() ?? '—');
                    final boostType = row['boostType']?.toString() ?? '';
                    final duration = row['durationDays']?.toString() ?? '';
                    final price = row['price']?.toString() ?? '';
                    final status = row['status']?.toString() ?? 'pending';
                    final canAct = status == 'pending';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(storeName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text('Type: $boostType | Duration: $duration days | Price: \$$price', style: GoogleFonts.tajawal(fontSize: 12)),
                            const SizedBox(height: 6),
                            Text('Status: $status', style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
                            if (canAct) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => _patch(id, 'rejected'),
                                    child: Text('Reject', style: GoogleFonts.tajawal(color: AppColors.error)),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _patch(id, 'approved'),
                                    style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                                    child: Text('Approve', style: GoogleFonts.tajawal()),
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
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _patch(String id, String status) async {
    final st = await AdminRepository.instance.patchBoostRequestStatus(id, status: status);
    if (!mounted) return;
    if (st is FeatureFailure<FeatureUnit>) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(st.message, style: GoogleFonts.tajawal())));
      return;
    }
    _reload();
  }
}
