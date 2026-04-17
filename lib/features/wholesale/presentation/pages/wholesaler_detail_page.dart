import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/services/chat_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../communication/presentation/unified_chat_page.dart';
import '../../../reviews/presentation/widgets/reviews_section.dart';
import '../../../reviews/data/reviews_repository.dart';
import '../../../reviews/domain/review_model.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/wholesale_repository.dart';
import '../../domain/wholesale_product_model.dart';
import '../../domain/wholesaler_model.dart';
import 'wholesaler_product_detail_page.dart';
import 'wholesaler_products_market_page.dart';

/// ØµÙØ­Ø© ØªÙØ§ØµÙŠÙ„ ØªØ§Ø¬Ø± Ø¬Ù…Ù„Ø© â€” Ø¨Ø§Ù†Ø±ØŒ Ø¨Ø±ÙˆÙØ§ÙŠÙ„ØŒ Ø¨Ø­Ø«ØŒ Ù…Ù†ØªØ¬Ø§ØªØŒ ØªÙˆØµÙŠÙ„ØŒ Ù…Ø­Ø§Ø¯Ø«Ø© (Ø¨Ø¯ÙˆÙ† Ø¹Ø±Ø¶ Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ).
class WholesalerDetailPage extends StatefulWidget {
  const WholesalerDetailPage({super.key, required this.wholesaler});

  final WholesalerModel wholesaler;

  @override
  State<WholesalerDetailPage> createState() => _WholesalerDetailPageState();
}

class _WholesalerDetailPageState extends State<WholesalerDetailPage> {
  final _search = TextEditingController();
  List<WholesaleProduct> _products = [];
  bool _loading = true;
  String? _error;
  String? _filterCategoryId;

  WholesalerModel get w => widget.wholesaler;

  List<String> _bannerUrls() {
    final u = <String>[];
    final c = w.coverImage.trim();
    final l = w.logo.trim();
    if (c.isNotEmpty) u.add(webSafeImageUrl(c));
    if (l.isNotEmpty && l != c) u.add(webSafeImageUrl(l));
    while (u.length < 3) {
      u.add(u.isNotEmpty ? u.first : '');
    }
    return u.take(3).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await WholesaleRepository.instance.getWholesalerProducts(w.id);
      if (mounted) {
        setState(() {
          _products = switch (state) {
            FeatureSuccess(:final data) => data,
            _ => <WholesaleProduct>[],
          };
        });
      }
    } on Object {
      debugPrint('[WholesalerDetailPage] _loadProducts failed.');
      if (mounted) setState(() => _error = 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª Ø­Ø§Ù„ÙŠØ§Ù‹.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat() async {
    final store = context.read<StoreController>();
    final myEmail = store.profile?.email.trim() ?? '';
    if (myEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ø³Ø¬Ù‘Ù„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„ÙØªØ­ Ø§Ù„Ù…Ø­Ø§Ø¯Ø«Ø©', style: GoogleFonts.tajawal())),
      );
      return;
    }
    if (w.ownerId.trim().isEmpty || w.email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ù„Ø§ ÙŠØªÙˆÙØ± Ø¨Ø±ÙŠØ¯ Ù…Ø³Ø¬Ù‘Ù„ Ù„Ù‡Ø°Ø§ Ø§Ù„ØªØ§Ø¬Ø± Ø­Ø§Ù„ÙŠØ§Ù‹', style: GoogleFonts.tajawal())),
      );
      return;
    }
    try {
      final chatId = await ChatService().getOrCreateChat(
        otherUserId: w.ownerId.trim(),
        otherUserName: w.name,
        currentUserEmail: myEmail,
        otherUserEmail: w.email.trim(),
        currentUserPhone: '',
        otherUserPhone: '',
        chatType: 'wholesale',
        referenceId: w.id,
        referenceName: w.name,
        referenceImageUrl: w.logo.trim().isNotEmpty ? w.logo : w.coverImage,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => UnifiedChatPage.resume(existingChatId: chatId, threadTitle: w.name),
        ),
      );
    } on Object {
      debugPrint('[WholesalerDetailPage] _openChat failed.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ØªØ¹Ø°Ø± ÙØªØ­ Ø§Ù„Ù…Ø­Ø§Ø¯Ø«Ø© Ø­Ø§Ù„ÙŠØ§Ù‹.', style: GoogleFonts.tajawal())),
      );
    }
  }

  Future<void> _openReviewsDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 8),
              Text('ØªÙ‚ÙŠÙŠÙ…Ø§Øª ØªØ§Ø¬Ø± Ø§Ù„Ø¬Ù…Ù„Ø©', textAlign: TextAlign.center, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 17)),
              ReviewsSection(targetId: w.id, targetType: 'wholesaler', title: 'ÙƒÙ„ Ø§Ù„Ù…Ø±Ø§Ø¬Ø¹Ø§Øª'),
            ],
          ),
        ),
      ),
    );
  }

  List<WholesaleProduct> _filtered() {
    var list = _products;
    if (_filterCategoryId != null) {
      list = list.where((p) => p.categoryId == _filterCategoryId).toList();
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final banners = _bannerUrls();
    final deliveryLine = [
      if (w.deliveryDays != null) 'Ù…Ø¯Ø© Ø§Ù„ØªÙˆØµÙŠÙ„: ${w.deliveryDays} ÙŠÙˆÙ…',
      if (w.deliveryFee != null) 'Ø±Ø³ÙˆÙ… Ø§Ù„ØªÙˆØµÙŠÙ„: ${w.deliveryFee!.toStringAsFixed(2)} Ø¯.Ø£',
    ].join(' Â· ');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text(w.name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => WholesalerProductsMarketPage(wholesaler: w)),
              );
            },
            icon: const Icon(Icons.inventory_2_outlined, color: Colors.white),
            label: Text('ÙƒÙ„ Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª', style: GoogleFonts.tajawal(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryOrange,
        onRefresh: _loadProducts,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(
              height: 200,
              child: CarouselSlider.builder(
                itemCount: banners.length,
                itemBuilder: (context, index, _) {
                  final url = banners[index];
                  if (url.isEmpty) {
                    return Container(
                      color: AppColors.primaryOrange,
                      alignment: Alignment.center,
                      child: Text('AmmarJo', style: GoogleFonts.tajawal(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    );
                  }
                  return AmmarCachedImage(imageUrl: url, width: double.infinity, height: 200, fit: BoxFit.cover);
                },
                options: CarouselOptions(
                  height: 200,
                  viewportFraction: 1,
                  enableInfiniteScroll: banners.where((e) => e.isNotEmpty).length > 1,
                  autoPlay: banners.where((e) => e.isNotEmpty).length > 1,
                  autoPlayInterval: const Duration(seconds: 4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundImage: w.logo.trim().isNotEmpty ? NetworkImage(webSafeImageUrl(w.logo.trim())) : null,
                    child: w.logo.trim().isEmpty ? const Icon(Icons.warehouse_outlined, size: 32) : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(w.name, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 4),
                        FutureBuilder<FeatureState<RatingAggregate>>(
                          future: ReviewsRepository.instance.getAggregate(targetId: w.id, targetType: 'wholesaler'),
                          builder: (context, snap) {
                            final data = snap.data;
                            final r = data is FeatureSuccess<RatingAggregate>
                                ? data.data.averageRating
                                : 0.0;
                            final total = data is FeatureSuccess<RatingAggregate>
                                ? data.data.totalReviews
                                : 0;
                            return _WholesalerRatingBadge(
                              rating: r,
                              totalReviews: total,
                              onTap: _openReviewsDialog,
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(w.category, textAlign: TextAlign.right, style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13)),
                        Text(w.city, textAlign: TextAlign.right, style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13)),
                        if (deliveryLine.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(deliveryLine, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.darkOrange, fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _openChat,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          label: Text('Ù…Ø­Ø§Ø¯Ø«Ø© Ù…Ø¹ Ø§Ù„ØªØ§Ø¬Ø±', style: GoogleFonts.tajawal(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (w.description.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(w.description, textAlign: TextAlign.right, style: GoogleFonts.tajawal(height: 1.4)),
              ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                final categories = <String>{for (final p in _products) if ((p.categoryId ?? '').trim().isNotEmpty) p.categoryId!.trim()}.toList()..sort();
                if (categories.isEmpty) return const SizedBox.shrink();
                return SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: FilterChip(
                          label: Text('ÙƒÙ„ Ø§Ù„Ø£Ù‚Ø³Ø§Ù…', style: GoogleFonts.tajawal(fontSize: 12)),
                          selected: _filterCategoryId == null,
                          onSelected: (_) => setState(() => _filterCategoryId = null),
                          selectedColor: AppColors.primaryOrange.withValues(alpha: 0.25),
                        ),
                      ),
                      ...categories.map((c) {
                        return Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: FilterChip(
                            label: Text(c, style: GoogleFonts.tajawal(fontSize: 12)),
                            selected: _filterCategoryId == c,
                            onSelected: (_) => setState(() => _filterCategoryId = c),
                            selectedColor: AppColors.primaryOrange.withValues(alpha: 0.25),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'Ø¨Ø­Ø« ÙÙŠ Ù…Ù†ØªØ¬Ø§Øª Ù‡Ø°Ø§ Ø§Ù„ØªØ§Ø¬Ø±',
                  hintStyle: GoogleFonts.tajawal(),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Ø§Ù„Ù…Ù†ØªØ¬Ø§Øª', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: GoogleFonts.tajawal(color: AppColors.error)),
              )
            else ...[
              if (_filtered().isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ù„Ø§ Ù…Ù†ØªØ¬Ø§Øª Ù…Ø·Ø§Ø¨Ù‚Ø©.', textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                )
              else
                ..._filtered().map(
                  (p) => Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: ListTile(
                      leading: p.imageUrl.trim().isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(webSafeImageUrl(p.imageUrl), width: 56, height: 56, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.inventory_2_outlined),
                      title: Text(p.name, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      subtitle: Text('Ø§Ù„ÙˆØ­Ø¯Ø©: ${p.unit}', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 12)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => WholesalerProductDetailPage(
                              wholesalerId: w.id,
                              wholesalerName: w.name,
                              wholesalerOwnerId: w.ownerId,
                              wholesalerEmail: w.email,
                              product: p,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WholesalerRatingBadge extends StatelessWidget {
  const _WholesalerRatingBadge({
    required this.rating,
    required this.totalReviews,
    required this.onTap,
  });

  final double rating;
  final int totalReviews;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.orange.shade100.withValues(alpha: 0.95),
                Colors.deepOrange.shade200.withValues(alpha: 0.95),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(99),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 4),
              Text(
                rating.toStringAsFixed(1),
                style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 4),
              Text(
                '($totalReviews ØªÙ‚ÙŠÙŠÙ…)',
                style: GoogleFonts.tajawal(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

