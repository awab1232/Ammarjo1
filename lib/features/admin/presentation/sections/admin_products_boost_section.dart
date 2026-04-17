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
  Future<List<Map<String, dynamic>>>? _future;

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

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    final raw = await BackendAdminClient.instance.fetchFilteredProducts(limit: 300);
    final itemsRaw = raw?['items'];
    if (itemsRaw is! List) return <Map<String, dynamic>>[];
    return itemsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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
        final rows = snapshot.requireData;
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
                              title: Text('Boosted', style: GoogleFonts.tajawal(fontSize: 12)),
                              dense: true,
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              value: isTrending,
                              onChanged: (v) async {
                                await _patchBoost(row, isTrending: v);
                              },
                              title: Text('Trending', style: GoogleFonts.tajawal(fontSize: 12)),
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
