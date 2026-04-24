import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesaler_model.dart';
import 'wholesaler_detail_page.dart';
import 'wholesaler_products_market_page.dart';

class WholesaleMarketplacePage extends StatefulWidget {
  const WholesaleMarketplacePage({super.key});

  @override
  State<WholesaleMarketplacePage> createState() => _WholesaleMarketplacePageState();
}

class _WholesaleMarketplacePageState extends State<WholesaleMarketplacePage> {
  static const int _pageSize = 10;
  final TextEditingController _search = TextEditingController();
  final List<WholesalerModel> _stores = <WholesalerModel>[];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  String _cat = 'all';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _stores.clear();
      _nextCursor = null;
      _hasMore = true;
    });
    try {
      final resultState = await WholesaleRepository.instance.getWholesalers(limit: _pageSize);
      if (!mounted) return;
      if (resultState case FeatureSuccess(:final data)) {
        setState(() {
          _stores.addAll(data.items);
          _nextCursor = data.nextCursor;
          _hasMore = _nextCursor != null;
        });
      } else {
        resultState.logIfNotSuccess('WholesaleMarketplace._reload');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر تحميل سوق الجملة.', style: GoogleFonts.tajawal())),
          );
        }
      }
    } on Object {
      debugPrint('[WholesaleMarketplace] _reload failed.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحميل سوق الجملة.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _nextCursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final resultState = await WholesaleRepository.instance.getWholesalers(
        limit: _pageSize,
        cursor: _nextCursor,
      );
      if (!mounted) return;
      if (resultState case FeatureSuccess(:final data)) {
        setState(() {
          _stores.addAll(data.items);
          _nextCursor = data.nextCursor;
          _hasMore = _nextCursor != null;
        });
      } else {
        resultState.logIfNotSuccess('WholesaleMarketplace._loadMore');
      }
    } on Object {
      debugPrint('[WholesaleMarketplace] _loadMore failed.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<WholesalerModel> _filtered() {
    final term = _search.text.trim().toLowerCase();
    final list = _stores.where((w) {
      final passSearch = term.isEmpty || w.name.toLowerCase().contains(term) || w.category.toLowerCase().contains(term);
      final passCat = _cat == 'all' || w.category == _cat;
      return passSearch && passCat;
    }).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final uid = UserSession.currentUid;
    if (!UserSession.isLoggedIn || uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('سوق الجملة', style: GoogleFonts.tajawal())),
        body: Center(child: Text('سجّل الدخول كصاحب متجر', style: GoogleFonts.tajawal())),
      );
    }
    final rows = _filtered();
    final categories = <String>{for (final d in _stores) d.category}.where((e) => e.isNotEmpty).toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text('سوق الجملة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: AppColors.primaryOrange,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: kIsWeb ? 44 : 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(12, kIsWeb ? 4 : 8, 12, kIsWeb ? 6 : 8),
                itemCount: 1 + categories.length,
                separatorBuilder: (_, _) => SizedBox(width: kIsWeb ? 6 : 8),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    final sel = _cat == 'all';
                    return FilterChip(
                      label: Text('الكل', style: GoogleFonts.tajawal(fontSize: kIsWeb ? 12 : 14, fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
                      selected: sel,
                      onSelected: (_) => setState(() => _cat = 'all'),
                      selectedColor: AppColors.primaryOrange.withValues(alpha: 0.25),
                    );
                  }
                  final c = categories[i - 1];
                  final sel = _cat == c;
                  return FilterChip(
                    label: Text(c, style: GoogleFonts.tajawal(fontSize: kIsWeb ? 12 : 14, fontWeight: sel ? FontWeight.w800 : FontWeight.w500)),
                    selected: sel,
                    onSelected: (_) => setState(() => _cat = c),
                    selectedColor: AppColors.primaryOrange.withValues(alpha: 0.25),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو التصنيف',
                  hintStyle: GoogleFonts.tajawal(),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: const [
                        SizedBox(height: 8),
                        HomeStoreListSkeleton(rows: 6),
                      ],
                    )
                  : rows.isEmpty
                      ? EmptyStateWidget(
                          type: EmptyStateType.wholesale,
                          onAction: _reload,
                          actionLabel: 'إعادة المحاولة',
                        )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: rows.length + 1,
                      itemBuilder: (context, i) {
                        if (i >= rows.length) {
                          if (!_hasMore) return const SizedBox(height: 12);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: FilledButton(
                                onPressed: _loadingMore ? null : _loadMore,
                                child: Text(_loadingMore ? 'جاري التحميل...' : 'تحميل المزيد', style: GoogleFonts.tajawal()),
                              ),
                            ),
                          );
                        }
                        final w = rows[i];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(builder: (_) => WholesalerDetailPage(wholesaler: w)),
                              );
                            },
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: w.logo.trim().isNotEmpty ? NetworkImage(webSafeImageUrl(w.logo)) : null,
                                child: w.logo.trim().isEmpty ? const Icon(Icons.warehouse_outlined) : null,
                              ),
                              title: Text(w.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                'التصنيف: ${w.category}\nالمدينة: ${w.city}',
                                style: GoogleFonts.tajawal(fontSize: 12),
                                textAlign: TextAlign.right,
                              ),
                              trailing: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                                onPressed: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(builder: (_) => WholesalerProductsMarketPage(wholesaler: w)),
                                  );
                                },
                                child: Text('عرض المنتجات', style: GoogleFonts.tajawal(color: Colors.white)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

