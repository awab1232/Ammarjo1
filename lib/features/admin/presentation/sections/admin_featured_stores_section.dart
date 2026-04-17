import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/backend_admin_client.dart';
import '../../data/admin_repository.dart';

class AdminFeaturedStoresSection extends StatefulWidget {
  const AdminFeaturedStoresSection({super.key});

  @override
  State<AdminFeaturedStoresSection> createState() =>
      _AdminFeaturedStoresSectionState();
}

class _AdminFeaturedStoresSectionState extends State<AdminFeaturedStoresSection> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _loadStores();
    });
  }

  Future<List<Map<String, dynamic>>> _loadStores() async {
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    for (var i = 0; i < 30; i++) {
      final page =
          await BackendAdminClient.instance.fetchStores(limit: 100, offset: offset);
      final dataRaw = page?['items'];
      final data = dataRaw is List
          ? dataRaw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (data.isEmpty) break;
      rows.addAll(data);
      if (data.length < 100) break;
      offset += 100;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.orange),
          );
        }
        final stores = snapshot.requireData;
        if (stores.isEmpty) {
          return Center(
            child: Text(
              'لا توجد متاجر',
              style: GoogleFonts.tajawal(color: AppColors.textSecondary),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: stores.length,
            itemBuilder: (context, index) {
              final row = stores[index];
              final id = row['id']?.toString() ?? '';
              final name = row['name']?.toString() ?? id;
              final isFeatured = row['isFeatured'] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: SwitchListTile(
                  value: isFeatured,
                  onChanged: (v) async {
                    final st = await AdminRepository.instance.updateStoreFeatures(
                      id,
                      isFeatured: v,
                    );
                    if (!context.mounted) return;
                    if (st case FeatureFailure(:final message)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
                      );
                      return;
                    }
                    setState(() {
                      row['isFeatured'] = v;
                    });
                  },
                  title: Text(
                    name,
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    id,
                    style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  secondary: const Icon(Icons.storefront_outlined),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
