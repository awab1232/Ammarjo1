import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/admin_repository.dart';
import '../../data/backend_admin_client.dart';

class AdminProductsBoostSection extends StatefulWidget {
  const AdminProductsBoostSection({super.key});

  @override
  State<AdminProductsBoostSection> createState() =>
      _AdminProductsBoostSectionState();
}

class _AdminProductsBoostSectionState extends State<AdminProductsBoostSection> {
  Future<FeatureState<List<Map<String, dynamic>>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _loadProducts();
    });
  }

  Future<FeatureState<List<Map<String, dynamic>>>> _loadProducts() async {
    try {
      final raw =
          await BackendAdminClient.instance.fetchFilteredProducts(limit: 300);
      if (raw == null) {
        return FeatureState.missingBackend('admin_products_boost');
      }
      final itemsRaw = raw['items'];
      if (itemsRaw is! List) {
        return FeatureState.failure('admin_products_boost_invalid_response');
      }
      final items = <Map<String, dynamic>>[];
      for (final e in itemsRaw) {
        if (e is Map) items.add(Map<String, dynamic>.from(e));
      }
      return FeatureState.success(items);
    } on Object catch (e) {
      return FeatureState.failure('admin_products_boost_load_failed', e);
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

        final List<Map<String, dynamic>> rows;
        if (state is FeatureSuccess<List<Map<String, dynamic>>>) {
          rows = state.data;
        } else if (state is FeatureFailure<List<Map<String, dynamic>>>) {
          return _errorState(context, state.message, _reload);
        } else {
          state.logIfNotSuccess('admin_products_boost');
          return _errorState(
            context,
            'خدمة المنتجات غير متاحة حالياً',
            _reload,
          );
        }

        if (rows.isEmpty) {
          return Center(
            child: Text(
              'لا توجد منتجات',
              style: GoogleFonts.tajawal(color: AppColors.textSecondary),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final id = row['id']?.toString() ?? '';
              final name = row['name']?.toString() ?? id;
              final isBoosted = row['isBoosted'] == true;
              final isTrending = row['isTrending'] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        name,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              value: isBoosted,
                              onChanged: (v) async {
                                await _patchBoost(row, isBoosted: v);
                              },
                              title: Text('Boosted',
                                  style: GoogleFonts.tajawal(fontSize: 12)),
                              dense: true,
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              value: isTrending,
                              onChanged: (v) async {
                                await _patchBoost(row, isTrending: v);
                              },
                              title: Text('Trending',
                                  style: GoogleFonts.tajawal(fontSize: 12)),
                              dense: true,
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

  Future<void> _patchBoost(
    Map<String, dynamic> row, {
    bool? isBoosted,
    bool? isTrending,
  }) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final state = await AdminRepository.instance.updateProductBoost(
      id,
      isBoosted: isBoosted,
      isTrending: isTrending,
    );
    if (!mounted) return;
    if (state case FeatureFailure(:final message)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.tajawal())),
      );
      return;
    }
    setState(() {
      if (isBoosted != null) row['isBoosted'] = isBoosted;
      if (isTrending != null) row['isTrending'] = isTrending;
    });
  }
}
