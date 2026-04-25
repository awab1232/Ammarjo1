import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/jordan_regions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../data/local_storage_service.dart';
import '../../domain/models.dart';
import '../../domain/store_search_matcher.dart';
import '../store_controller.dart';
import 'product_details_page.dart';
import 'products_horizontal_section_page.dart';

/// بحث المتجر — فوري، عربي، مع فلاتر وعيّنات بحث وتأثير تحميل.
class StoreSearchPage extends StatefulWidget {
  const StoreSearchPage({super.key});

  @override
  State<StoreSearchPage> createState() => _StoreSearchPageState();
}

class _StoreSearchPageState extends State<StoreSearchPage> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final LocalStorageService _storage = LocalStorageService();
  Timer? _debounce;
  var _filters = const StoreSearchFilters();
  var _awaitingResults = false;
  List<String> _recent = <String>[];

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    _loadRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  Future<void> _loadRecent() async {
    final list = await _storage.getRecentSearches();
    if (mounted) setState(() => _recent = list);
  }

  void _onFocusChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _scheduleSearchCommit() {
    _debounce?.cancel();
    final text = _queryCtrl.text;
    final store = context.read<StoreController>();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = text.trim();
      if (!mounted) return;
      if (q.length < 2) {
        store.clearSearch();
        setState(() => _awaitingResults = false);
        return;
      }
      await store.performSearch(q);
      if (!mounted) return;
      await _storage.addRecentSearch(q);
      await _loadRecent();
      setState(() => _awaitingResults = false);
    });
    setState(() => _awaitingResults = true);
  }

  Future<void> _applyQueryFromRecent(String q) async {
    _queryCtrl.text = q;
    _queryCtrl.selection = TextSelection.collapsed(offset: q.length);
    setState(() {});
    _scheduleSearchCommit();
  }

  List<Product> _results(StoreController store) {
    final base = store.searchQuery.trim().isNotEmpty ? store.searchResults : store.products;
    return runStoreSearch(
      products: base,
      categories: store.categoriesForHomePage,
      query: _queryCtrl.text,
      filters: _filters,
    );
  }

  String _categoryTag(Product p, StoreController store) {
    for (final cid in p.categoryIds) {
      for (final c in store.categoriesForHomePage) {
        if (c.id == cid) return c.name;
      }
    }
    return 'مواد بناء';
  }

  void _openFilters(StoreController store) {
    final prices = store.products.map(storeProductPrimaryPrice).whereType<double>().toList();
    if (prices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا توجد أسعار لتحديد النطاق بعد.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    var minV = prices.reduce(math.min);
    var maxV = prices.reduce(math.max);
    if (maxV - minV < 0.02) {
      maxV = minV + 1.0;
    }
    var minF = _filters.minPrice ?? minV;
    var maxF = _filters.maxPrice ?? maxV;
    if (minF > maxF) {
      final t = minF;
      minF = maxF;
      maxF = t;
    }
    String? region = _filters.region;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.paddingOf(ctx).bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('تصفية النتائج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.navy)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setModal(() {
                            minF = minV;
                            maxF = maxV;
                            region = null;
                          });
                        },
                        child: Text('إعادة ضبط', style: GoogleFonts.tajawal(color: AppColors.orange)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'نطاق السعر (د.أ)',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  RangeSlider(
                    min: minV,
                    max: maxV,
                    values: RangeValues(
                      math.min(minF, maxF),
                      math.max(minF, maxF),
                    ),
                    activeColor: AppColors.orange,
                    onChanged: (v) {
                      setModal(() {
                        minF = v.start;
                        maxF = v.end;
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${minF.toStringAsFixed(2)} د.أ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      Text('${maxF.toStringAsFixed(2)} د.أ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'المنطقة (إن وُجدت في الاسم أو الوصف)',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: region,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    hint: Text('كل المناطق', style: GoogleFonts.tajawal()),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('— كل المناطق —', style: GoogleFonts.tajawal())),
                      ...kJordanRegions.map(
                        (r) => DropdownMenuItem<String?>(value: r, child: Text(r, style: GoogleFonts.tajawal())),
                      ),
                    ],
                    onChanged: (v) => setModal(() => region = v),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      final usePrice = (math.min(minF, maxF) > minV + 0.001) || (math.max(minF, maxF) < maxV - 0.001);
                      setState(() {
                        _filters = StoreSearchFilters(
                          minPrice: usePrice ? math.min(minF, maxF) : null,
                          maxPrice: usePrice ? math.max(minF, maxF) : null,
                          region: region,
                        );
                      });
                      Navigator.pop(ctx);
                    },
                    child: Text('تطبيق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    final hasQuery = _queryCtrl.text.trim().isNotEmpty;
    final results = _results(store);
    final showRecent = _focus.hasFocus && !hasQuery;
    final showEmpty = hasQuery && !_awaitingResults && !store.isSearching && results.isEmpty;
    final showList = hasQuery && !_awaitingResults && !store.isSearching && results.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: const AppBarBackButton(),
        title: Text('بحث المتجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.navy)),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Material(
              elevation: 2,
              shadowColor: AppColors.shadow,
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'تصفية',
                    onPressed: () => _openFilters(store),
                    icon: Icon(
                      Icons.tune_rounded,
                      color: _filters.hasActiveFilters ? AppColors.orange : AppColors.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      focusNode: _focus,
                      onChanged: (_) {
                        setState(() {});
                        _scheduleSearchCommit();
                      },
                      textInputAction: TextInputAction.search,
                      style: GoogleFonts.tajawal(fontSize: 16, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'ابحث بالاسم، الفئة، أو الكلمة…',
                        hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (hasQuery)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary),
                      onPressed: () {
                        _queryCtrl.clear();
                        context.read<StoreController>().clearSearch();
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),
          if (_filters.hasActiveFilters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (_filters.minPrice != null || _filters.maxPrice != null)
                    Chip(
                      label: Text(
                        'السعر: ${_filters.minPrice?.toStringAsFixed(1) ?? '—'} – ${_filters.maxPrice?.toStringAsFixed(1) ?? '—'}',
                        style: GoogleFonts.tajawal(fontSize: 12),
                      ),
                      onDeleted: () => setState(() {
                        _filters = _filters.copyWith(clearMinPrice: true, clearMaxPrice: true);
                      }),
                    ),
                  if (_filters.region != null && _filters.region!.isNotEmpty)
                    Chip(
                      label: Text(_filters.region!, style: GoogleFonts.tajawal(fontSize: 12)),
                      onDeleted: () => setState(() => _filters = _filters.copyWith(clearRegion: true)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: store.isLoading && store.products.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
                : showRecent
                    ? _RecentSearchesPanel(
                        items: _recent,
                        onSelect: _applyQueryFromRecent,
                        onRemove: (s) async {
                          await _storage.removeRecentSearch(s);
                          await _loadRecent();
                        },
                        onClear: () async {
                          await _storage.clearRecentSearches();
                          await _loadRecent();
                        },
                      )
                    : !hasQuery
                        ? _SearchHintPanel()
                        : (_awaitingResults || store.isSearching)
                            ? _SearchShimmerList()
                            : showEmpty
                                ? _NoResultsPanel(
                                    onContact: () {
                                      // REMOVED: legacy WordPress WpPageScreen — use in-app support / BackendOrdersClient
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) => Scaffold(
                                            appBar: AppBar(title: const Text('تواصل معنا')),
                                            body: const Center(
                                              child: Text('للتواصل يرجى استخدام الدعم داخل التطبيق.'),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    onViewAll: () {
                                      Navigator.of(context).push<void>(
                                        MaterialPageRoute<void>(
                                          builder: (_) => ProductsHorizontalSectionPage(
                                            title: 'جميع المنتجات',
                                            products: store.products,
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : showList
                                    ? Column(
                                        children: [
                                          Expanded(
                                            child: NotificationListener<ScrollNotification>(
                                              onNotification: (ScrollNotification n) {
                                                if (n.metrics.axis != Axis.vertical) return false;
                                                if (store.searchQuery.trim().isEmpty) return false;
                                                if (store.searchHasMore &&
                                                    !store.isLoadingMoreSearch &&
                                                    n.metrics.pixels >= n.metrics.maxScrollExtent - 240) {
                                                  store.loadMoreSearchResults();
                                                }
                                                return false;
                                              },
                                              child: ListView.separated(
                                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                                itemCount: results.length,
                                                separatorBuilder: (_, _) => const SizedBox(height: 12),
                                                itemBuilder: (context, i) {
                                                  return _SearchResultCard(
                                                    product: results[i],
                                                    categoryLabel: _categoryTag(results[i], store),
                                                    store: store,
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          if (store.isLoadingMoreSearch)
                                            const Padding(
                                              padding: EdgeInsets.only(bottom: 16),
                                              child: Center(
                                                child: SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: AppColors.orange,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SearchHintPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.manage_search_rounded, size: 64, color: AppColors.navy.withValues(alpha: 0.35)),
            const SizedBox(height: 16),
            Text(
              'ابدأ بالكتابة للبحث في كتالوج AmmarJo',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navy),
            ),
            const SizedBox(height: 8),
            Text(
              'يُدعم البحث بالعربية مع توحيد الألف والياء والهمزات.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentSearchesPanel extends StatelessWidget {
  const _RecentSearchesPanel({
    required this.items,
    required this.onSelect,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> items;
  final Future<void> Function(String) onSelect;
  final Future<void> Function(String) onRemove;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'لا توجد عمليات بحث حديثة بعد.',
            style: GoogleFonts.tajawal(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Text('عمليات البحث الأخيرة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.navy)),
            const Spacer(),
            TextButton(
              onPressed: onClear,
              child: Text('مسح الكل', style: GoogleFonts.tajawal(color: AppColors.orange, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((s) {
            return Material(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                onTap: () => onSelect(s),
                onLongPress: () => onRemove(s),
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 18, color: AppColors.orange.withValues(alpha: 0.9)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(s, style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'اضغط مطولاً على أي عبارة لحذفها.',
          style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SearchShimmerList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 8,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return Container(
            height: 108,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }
}

class _NoResultsPanel extends StatelessWidget {
  const _NoResultsPanel({required this.onContact, required this.onViewAll});

  final VoidCallback onContact;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 72, color: AppColors.slate.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              'لا توجد نتائج مطابقة',
              style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
            ),
            const SizedBox(height: 10),
            Text(
              'جرّب كلمات أخرى، أو عدّل التصفية، أو تصفّح كل المنتجات.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 15, color: AppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onViewAll,
                icon: const Icon(Icons.storefront_rounded),
                label: Text('عرض كل المنتجات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.orange,
                side: const BorderSide(color: AppColors.orange),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: onContact,
              icon: const Icon(Icons.support_agent_rounded),
              label: Text('تواصل مع الدعم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.product,
    required this.categoryLabel,
    required this.store,
  });

  final Product product;
  final String categoryLabel;
  final StoreController store;

  @override
  Widget build(BuildContext context) {
    final image = webSafeFirstProductImage(product.images);
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: AppColors.shadow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(product: product)),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: image.isEmpty
                        ? ColoredBox(
                            color: AppColors.orangeLight,
                            child: Icon(Icons.image_outlined, color: AppColors.orange.withValues(alpha: 0.45), size: 36),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(8),
                            child: AmmarCachedImage(
                              imageUrl: image,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              productTileStyle: true,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: AppColors.navy,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.navy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            categoryLabel,
                            style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.navy),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          store.formatPrice(product.price),
                          style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: AppColors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'عرض المنتج',
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: (_) => ProductDetailsPage(product: product)),
                        );
                      },
                      icon: Icon(Icons.visibility_outlined, color: AppColors.navy.withValues(alpha: 0.85)),
                    ),
                    IconButton(
                      tooltip: 'إضافة للسلة',
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        await store.addToCart(product);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تمت الإضافة إلى السلة', style: GoogleFonts.tajawal()),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_shopping_cart_rounded, color: AppColors.orange),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
