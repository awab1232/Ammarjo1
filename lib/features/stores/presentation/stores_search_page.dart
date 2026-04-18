import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/config/backend_orders_config.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/widgets/feature_state_builder.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../../core/widgets/home_page_shimmers.dart';
import '../../store/presentation/store_controller.dart';
import '../data/stores_repository.dart';
import '../domain/store_model.dart';
import 'store_detail_page.dart';
import 'widgets/store_card.dart';

/// بحث بسيط في أسماء المتاجر المعتمدة.
class StoresSearchPage extends StatefulWidget {
  const StoresSearchPage({super.key});

  @override
  State<StoresSearchPage> createState() => _StoresSearchPageState();
}

class _StoresSearchPageState extends State<StoresSearchPage> {
  final _query = TextEditingController();
  int _reloadNonce = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<StoreModel> _filter(List<StoreModel> list, String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return list;
    return list.where((s) => s.name.toLowerCase().contains(t) || s.description.toLowerCase().contains(t)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final storeController = context.watch<StoreController>();
    final city = storeController.profile?.city?.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text('بحث المتاجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              textAlign: TextAlign.right,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الوصف…',
                hintStyle: GoogleFonts.tajawal(),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryOrange),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: BackendOrdersConfig.useBackendStoreReads && _query.text.trim().isNotEmpty
                ? FutureBuilder<FeatureState<List<StoreModel>>>(
                    key: ValueKey<String>('search-$_reloadNonce-${_query.text}'),
                    future: StoresRepository.instance.searchStoresByText(
                      _query.text,
                      city: city,
                      limit: 50,
                    ),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: const [
                            SizedBox(height: 12),
                            HomeStoreListSkeleton(rows: 6),
                          ],
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();
                      return buildFeatureStateUi<List<StoreModel>>(
                        context: context,
                        state: snap.data!,
                        onRetry: () => setState(() => _reloadNonce++),
                        dataBuilder: (ctx, all) => _buildResultsList(all),
                      );
                    },
                  )
                : FutureBuilder<FeatureState<List<StoreModel>>>(
                    key: ValueKey<String>('list-$_reloadNonce-${city ?? ''}'),
                    future: StoresRepository.instance.fetchApprovedStores(city: city),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: const [
                            SizedBox(height: 12),
                            HomeStoreListSkeleton(rows: 6),
                          ],
                        );
                      }
                      if (!snap.hasData) return const SizedBox.shrink();
                      return buildFeatureStateUi<List<StoreModel>>(
                        context: context,
                        state: snap.data!,
                        onRetry: () => setState(() => _reloadNonce++),
                        dataBuilder: (ctx, all) {
                          final filtered = _filter(all, _query.text);
                          return _buildResultsList(filtered);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(List<StoreModel> stores) {
    if (stores.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storefront_outlined, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('لا نتائج', style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: stores.length,
      itemBuilder: (context, i) {
        final s = stores[i];
        return StoreCard(
          store: s,
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => StoreDetailPage(store: s)),
            );
          },
        );
      },
    );
  }
}
