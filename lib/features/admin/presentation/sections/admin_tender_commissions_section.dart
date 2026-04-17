import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../data/admin_repository.dart';

class AdminTenderCommissionsSection extends StatefulWidget {
  const AdminTenderCommissionsSection({super.key});

  @override
  State<AdminTenderCommissionsSection> createState() => _AdminTenderCommissionsSectionState();
}

class _AdminTenderCommissionsSectionState extends State<AdminTenderCommissionsSection> {
  bool _loading = true;
  int _total = 0;
  int _approved = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final state = await AdminRepository.instance.fetchTenders();
    final items = switch (state) {
      FeatureSuccess(:final data) => data,
      _ => const <Map<String, dynamic>>[],
    };
    _total = items.length;
    _approved = items.where((e) => (e['status']?.toString() ?? '') == 'approved').length;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('عمولات المناقصات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        Text('إجمالي المناقصات: $_total', style: GoogleFonts.tajawal(height: 1.45)),
        Text('المعتمدة: $_approved', style: GoogleFonts.tajawal(height: 1.45)),
      ],
    );
  }
}
