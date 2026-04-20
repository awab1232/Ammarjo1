import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/home_repository.dart';
import '../../../../core/models/home_section.dart';
import '../../../../core/services/backend_orders_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../../../core/seo/seo_routes.dart';
import '../../domain/store_model.dart';
import '../store_detail_page.dart';

/// Section header with consistent spacing (avoids overlap with neighbors).
class StoresHomeMarketingSectionTitle extends StatelessWidget {
  const StoresHomeMarketingSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal cards for `home_sections` (admin: المتاجر → الأقسام الرئيسية).
class StoresHomeSectionsCardsStrip extends StatelessWidget {
  const StoresHomeSectionsCardsStrip({super.key});

  Future<FeatureState<List<HomeSection>>> _safeHomeSections() async {
    try {
      final state = await HomeRepository.instance.getSections();
      return switch (state) {
        FeatureSuccess<List<HomeSection>>(:final data) => FeatureState.success(data),
        _ => FeatureState.success(const <HomeSection>[]),
      };
    } on Object {
      return FeatureState.success(const <HomeSection>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeatureState<List<HomeSection>>>(
      future: _safeHomeSections(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[StoresHomeSectionsCardsStrip] ${snap.error}');
          return const SizedBox.shrink();
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const HomeHorizontalCardsSkeleton(height: 148, cardWidth: 158, count: 5, spacing: 12);
        }
        final state = snap.data;
        final sections = switch (state) {
          FeatureSuccess<List<HomeSection>>(:final data) => data,
          _ => const <HomeSection>[],
        };
        if (sections.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'لا توجد أقسام بعد. أضفها من لوحة التحكم.',
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
            ),
          );
        }
        return SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            itemCount: sections.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final s = sections[i];
              final img = webSafeImageUrl((s.image ?? '').trim());
              return SizedBox(
                width: 158,
                child: Material(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        SeoRoutes.category(s.name),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: img.isEmpty
                              ? ColoredBox(
                                  color: AppColors.lightOrange,
                                  child: Icon(Icons.store_mall_directory_rounded, color: AppColors.primaryOrange, size: 40),
                                )
                              : AmmarCachedImage(imageUrl: img, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                          child: Text(
                            s.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.linkUrl,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final String? linkUrl;

  Future<void> _openLink() async {
    final raw = linkUrl?.trim() ?? '';
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final url = webSafeImageUrl(imageUrl);
    final hasLink = (linkUrl?.trim() ?? '').isNotEmpty;
    return SizedBox(
      width: 168,
      child: Material(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hasLink ? _openLink : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: url.isEmpty
                    ? ColoredBox(color: AppColors.lightOrange, child: Icon(Icons.local_offer_rounded, color: AppColors.primaryOrange, size: 36))
                    : AmmarCachedImage(imageUrl: url, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 14)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Offers row from `GET /home/cms` (admin: إدارة البنرات والصفحة الرئيسية).
class StoresHomeOffersStrip extends StatelessWidget {
  const StoresHomeOffersStrip({super.key});

  Future<Map<String, dynamic>> _safeHomeCms() async {
    try {
      final cms = await BackendOrdersClient.instance.fetchHomeCms();
      return cms ?? <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  static List<Map<String, dynamic>> _parseOffers(Map<String, dynamic>? cms) {
    final raw = cms?['offers'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _safeHomeCms(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[StoresHomeOffersStrip] ${snap.error}');
          return const SizedBox.shrink();
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const HomeOffersStripSkeleton();
        }
        final offers = _parseOffers(snap.data);
        if (offers.isEmpty) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            itemCount: offers.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final o = offers[i];
              final title = (o['title'] ?? '').toString();
              final subtitle = (o['subtitle'] ?? '').toString();
              final imageUrl = (o['imageUrl'] ?? o['image'] ?? '').toString();
              final linkRaw = (o['linkUrl'] ?? o['link'] ?? o['url'] ?? '').toString().trim();
              final linkUrl = linkRaw.isEmpty ? null : linkRaw;
              return _OfferTile(
                title: title.isEmpty ? 'عرض' : title,
                subtitle: subtitle,
                imageUrl: imageUrl,
                linkUrl: linkUrl,
              );
            },
          ),
        );
      },
    );
  }
}

class _CompactStoreTile extends StatelessWidget {
  const _CompactStoreTile({required this.store, required this.onTap});

  final StoreModel store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logo = webSafeImageUrl(store.logo);
    return SizedBox(
      width: 118,
      child: Material(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                ClipOval(
                  child: logo.isEmpty
                      ? CircleAvatar(radius: 28, backgroundColor: AppColors.lightOrange, child: Icon(Icons.storefront_rounded, color: AppColors.primaryOrange))
                      : AmmarCachedImage(imageUrl: logo, width: 56, height: 56, fit: BoxFit.cover),
                ),
                const SizedBox(height: 8),
                Text(
                  store.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Featured / boosted stores first, then alphabetical cap at [maxItems].
class StoresHomeMostRequestedStrip extends StatelessWidget {
  const StoresHomeMostRequestedStrip({
    super.key,
    required this.futureStores,
    this.maxItems = 8,
  });

  final Future<FeatureState<List<StoreModel>>> futureStores;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FeatureState<List<StoreModel>>>(
      future: futureStores,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const HomeStoreChipsSkeleton(count: 6);
        }
        final state = snap.data;
        final all = switch (state) {
          FeatureSuccess<List<StoreModel>>(:final data) => List<StoreModel>.from(data),
          _ => const <StoreModel>[],
        };
        final rest = all.where((s) => s.id.toLowerCase().trim() != 'ammarjo').toList();
        rest.sort((a, b) {
          final f = (b.isFeatured ? 1 : 0).compareTo(a.isFeatured ? 1 : 0);
          if (f != 0) return f;
          final g = (b.isBoosted ? 1 : 0).compareTo(a.isBoosted ? 1 : 0);
          if (g != 0) return g;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        final pick = rest.take(maxItems).toList();
        if (pick.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            itemCount: pick.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final s = pick[i];
              return _CompactStoreTile(
                store: s,
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => StoreDetailPage(store: s)),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// Second full-width banner from `GET /home/cms` (`bottomBanner`).
class StoresHomeBottomMarketingBanner extends StatelessWidget {
  const StoresHomeBottomMarketingBanner({super.key});

  Future<Map<String, dynamic>> _safeHomeCms() async {
    try {
      final cms = await BackendOrdersClient.instance.fetchHomeCms();
      return cms ?? <String, dynamic>{};
    } on Object {
      return <String, dynamic>{};
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _safeHomeCms(),
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint('[StoresHomeBottomMarketingBanner] ${snap.error}');
          return const SizedBox.shrink();
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const HomeBottomBannerSkeleton();
        }
        final cms = snap.data;
        final bottom = cms?['bottomBanner'];
        if (bottom is! Map) return const SizedBox.shrink();
        final m = Map<String, dynamic>.from(bottom);
        final url = webSafeImageUrl((m['imageUrl'] ?? m['image'] ?? '').toString());
        if (url.isEmpty) return const SizedBox.shrink();
        final linkRaw = (m['linkUrl'] ?? m['link'] ?? m['url'] ?? '').toString().trim();
        final linkUri = linkRaw.isEmpty ? null : Uri.tryParse(linkRaw);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: linkUri == null
                    ? null
                    : () async {
                        await launchUrl(linkUri, mode: LaunchMode.externalApplication);
                      },
                child: SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AmmarCachedImage(imageUrl: url, fit: BoxFit.cover, width: double.infinity, height: 120),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Text(
                            (m['title'] ?? '').toString(),
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
