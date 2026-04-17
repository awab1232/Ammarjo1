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
  Future<FeatureState<List<Map<String, dynamic>>>>? _future;

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

  Future<FeatureState<List<Map<String, dynamic>>>> _loadStores() async {
    try {
      final rows = <Map<String, dynamic>>[];
      var offset = 0;
      for (var i = 0; i < 30; i++) {
        final page = await BackendAdminClient.instance
            .fetchStores(limit: 100, offset: offset);
        if (page == null) {
          return FeatureState.missingBackend('admin_featured_stores');
        }
        final dataRaw = page['items'];
        final data = <Map<String, dynamic>>[];
        if (dataRaw is List) {
          for (final e in dataRaw) {
            if (e is Map) data.add(Map<String, dynamic>.from(e));
          }
        }
        if (data.isEmpty) break;
        rows.addAll(data);
        if (data.length < 100) break;
        offset += 100;
      }
      return FeatureState.success(rows);
    } on Object catch (e) {
      return FeatureState.failure('admin_featured_stores_load_failed', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
      future: _future,
      builder: (context, snap) {
        final state = snap.data;
        if (state == null) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.orange),
          );
        }

        final List<Map<String, dynamic>> stores;
        switch (state) {
          case FeatureSuccess<List<Map<String, dynamic>>>(:final data):
            stores = data;
          case FeatureFailure<List<Map<String, dynamic>>>(:final message):
            return _errorState(context, message, _reload);
          case FeatureMissingBackend<List<Map<String, dynamic>>>():
          case FeatureAdminNotWired<List<Map<String, dynamic>>>():
          case FeatureAdminMissingEndpoint<List<Map<String, dynamic>>>():
          case FeatureCriticalPublicDataFailure<List<Map<String, dynamic>>>():
            state.logIfNotSuccess('admin_featured_stores');
            return _errorState(
              context,
              'خدمة المتاجر غير متاحة حالياً',
              _reload,
            );
        }

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

  Widget _errorState(BuildContext context, String message, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
            ),
          ],
        ),
      ),
    );
  }
}
