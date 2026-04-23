import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/jordan_regions.dart';
import '../../../core/contracts/feature_state.dart';
import '../../../core/firebase/user_notifications_repository.dart';
import '../../../core/domain/store_type.dart';
import '../../../core/logging/backend_fallback_logger.dart';
import '../../../core/session/backend_identity_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_bar_back_button.dart';
import '../../support/presentation/open_support_chat.dart';
import '../../reviews/presentation/widgets/reviews_section.dart';
import 'sections/store_owner_analytics_section.dart';
import '../../../core/utils/store_product_discount.dart';
import '../../../core/utils/web_image_url.dart';
import '../../../core/widgets/ammar_cached_image.dart';
import '../../../core/widgets/full_screen_image_viewer.dart';
import '../data/owner_entity_doc.dart' show OwnerEntityDoc, OwnerStoreSnapshot, StoreCommissionView;
import '../data/store_owner_repository.dart';
import '../../stores/domain/shipping_policy.dart';
import '../../stores/domain/store_opening_hours.dart';
import '../../tenders/presentation/sections/store_tenders_tab.dart';
import 'sections/store_owner_tender_commissions_tab.dart';

/// حالات الطلب لمتجر (من اليمين لليسار في سير العمل). «إلغاء» حالة نهائية — بدون عمولة.
const List<String> kStoreOrderStatuses = [
  'قيد المراجعة',
  'قيد التحضير',
  'قيد التوصيل',
  'تم التسليم',
  'إلغاء',
];

String _storeOwnerFormatDateShort(dynamic ts) {
  if (ts == null) return '—';
  if (ts is Map) {
    final s = ts['seconds'];
    if (s is int) {
      return DateTime.fromMillisecondsSinceEpoch(s * 1000).toString().split('.').first;
    }
  }
  if (ts is String && ts.isNotEmpty) {
    final p = DateTime.tryParse(ts);
    if (p != null) return p.toString().split('.').first;
  }
  return '—';
}

class _BoostRequestsTab extends StatefulWidget {
  const _BoostRequestsTab({required this.storeId});

  final String storeId;

  @override
  State<_BoostRequestsTab> createState() => _BoostRequestsTabState();
}

class _BoostRequestsTabState extends State<_BoostRequestsTab> {
  String _boostType = 'featured_store';
  int _durationDays = 7;
  bool _submitting = false;

  double _priceFor(String type, int days) {
    final base = switch (type) {
      'featured_store' => 3.0,
      'top_listing' => 2.5,
      'banner_ad' => 4.0,
      _ => 0.0,
    };
    return base * days;
  }

  @override
  Widget build(BuildContext context) {
    final price = _priceFor(_boostType, _durationDays);
    return FutureBuilder<FeatureState<List<Map<String, dynamic>>>>(
      future: StoreOwnerRepository.fetchBoostRequests(widget.storeId),
      builder: (context, snap) {
        final state = snap.data;
        final List<Map<String, dynamic>> rows;
        if (state is FeatureSuccess<List<Map<String, dynamic>>>) {
          rows = state.data;
        } else {
          rows = const <Map<String, dynamic>>[];
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Promote Store', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _boostType,
                      items: const [
                        DropdownMenuItem(value: 'featured_store', child: Text('featured_store')),
                        DropdownMenuItem(value: 'top_listing', child: Text('top_listing')),
                        DropdownMenuItem(value: 'banner_ad', child: Text('banner_ad')),
                      ],
                      onChanged: (v) => setState(() => _boostType = v ?? 'featured_store'),
                      decoration: const InputDecoration(labelText: 'Boost Type', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      value: _durationDays,
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 days')),
                        DropdownMenuItem(value: 7, child: Text('7 days')),
                        DropdownMenuItem(value: 14, child: Text('14 days')),
                      ],
                      onChanged: (v) => setState(() => _durationDays = v ?? 7),
                      decoration: const InputDecoration(labelText: 'Duration', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    Text('Price: \$${price.toStringAsFixed(2)}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              setState(() => _submitting = true);
                              try {
                                await StoreOwnerRepository.createBoostRequest(
                                  storeId: widget.storeId,
                                  boostType: _boostType,
                                  durationDays: _durationDays,
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('تم إرسال طلب الترويج', style: GoogleFonts.tajawal())),
                                );
                                setState(() {});
                              } on Object {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('تعذر إرسال الطلب', style: GoogleFonts.tajawal())),
                                );
                              } finally {
                                if (mounted) setState(() => _submitting = false);
                              }
                            },
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
                      child: Text(_submitting ? 'جاري الإرسال...' : 'Submit Request', style: GoogleFonts.tajawal()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('طلباتي السابقة', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              Text('لا توجد طلبات', textAlign: TextAlign.right, style: GoogleFonts.tajawal(color: AppColors.textSecondary))
            else
              ...rows.map((r) {
                final st = r['status']?.toString() ?? 'pending';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${r['boostType'] ?? ''} • ${r['durationDays'] ?? ''} days', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    subtitle: Text('Price: \$${r['price'] ?? ''}', style: GoogleFonts.tajawal()),
                    trailing: Text(st, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

/// لوحة صاحب المتجر — تبويبات: منتجات، أقسام، عروض، طلبات، مستحقات، إعدادات.
/// [storeId] يُؤخذ من `GET /auth/me` عبر [BackendIdentityController] (لا Firestore).
class StoreOwnerDashboard extends StatefulWidget {
  const StoreOwnerDashboard({super.key});

  @override
  State<StoreOwnerDashboard> createState() => _StoreOwnerDashboardState();
}

class _StoreOwnerDashboardState extends State<StoreOwnerDashboard> {
  late final Future<void> _boot = BackendIdentityController.instance.refresh();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _boot,
      builder: (context, bootSnap) {
        if (bootSnap.hasError) {
          debugPrint('❌ Error store owner dashboard: ${bootSnap.error}');
          return Scaffold(
            appBar: AppBar(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              leading: const AppBarBackButton(),
              title: Text('لوحة التحكم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text('تعذر تحميل لوحة المتجر', style: GoogleFonts.tajawal()),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(builder: (_) => const StoreOwnerDashboard()),
                      );
                    },
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        if (bootSnap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              leading: const AppBarBackButton(),
              title: Text('لوحة التحكم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
            body: const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
          );
        }
        return ListenableBuilder(
          listenable: BackendIdentityController.instance,
          builder: (context, _) {
            final role = (BackendIdentityController.instance.me?.role ?? '').trim().toLowerCase();
            final canAccess = role == 'store_owner' || role == 'admin';
            final storeId = BackendIdentityController.instance.me?.storeId?.trim();
        if (!canAccess || storeId == null || storeId.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: AppColors.primaryOrange,
              foregroundColor: Colors.white,
              leading: const AppBarBackButton(),
              title: Text('لوحة التحكم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  !canAccess
                      ? 'لا تملك صلاحية الوصول إلى لوحة المتجر.'
                      : 'لم يُعثر على متجر مرتبط بحسابك.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }
        return DefaultTabController(
          length: 11,
          child: Builder(
            builder: (context) {
              final tabController = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  final st = storeTypeFromBackendString(
                    BackendIdentityController.instance.me?.storeType,
                  );
                  final String titleBase = 'لوحة تحكم متجري';
                  final String title = switch (st) {
                    StoreType.construction => '$titleBase — مواد بناء',
                    StoreType.home => '$titleBase — أدوات منزلية',
                    StoreType.wholesale => '$titleBase — جملة',
                    StoreType.unknown => titleBase,
                  };
                  return Scaffold(
                    backgroundColor: AppColors.background,
                    appBar: AppBar(
                      backgroundColor: AppColors.primaryOrange,
                      foregroundColor: Colors.white,
                      leading: const AppBarBackButton(),
                      title: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      actions: [
                        IconButton(
                          tooltip: 'احصل على مساعدة',
                          icon: const Icon(Icons.support_agent, color: Colors.white),
                          onPressed: () => openSupportChat(context),
                        ),
                      ],
                      bottom: TabBar(
                        isScrollable: true,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white70,
                        indicatorColor: Colors.white,
                        tabs: [
                          Tab(child: Text('منتجاتي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('أقسامي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('العروض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('ترويج المتجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('طلباتي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('المناقصات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('عمولات المناقصات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('المستحقات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('مراجعات متجري', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('التحليلات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                          Tab(child: Text('إعدادات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700))),
                        ],
                      ),
                    ),
                    floatingActionButton: tabController.index == 0
                        ? FloatingActionButton(
                            backgroundColor: AppColors.primaryOrange,
                            foregroundColor: Colors.white,
                            onPressed: () => _openProductSheet(context, storeId: storeId),
                            child: const Icon(Icons.add_rounded),
                          )
                        : tabController.index == 1
                            ? FloatingActionButton(
                                backgroundColor: AppColors.primaryOrange,
                                foregroundColor: Colors.white,
                                onPressed: () => _openCategorySheet(context, storeId: storeId),
                                child: const Icon(Icons.folder_open_rounded),
                              )
                            : tabController.index == 2
                                ? FloatingActionButton(
                                    backgroundColor: AppColors.primaryOrange,
                                    foregroundColor: Colors.white,
                                    onPressed: () => _openOfferSheet(context, storeId: storeId),
                                    child: const Icon(Icons.local_offer_rounded),
                                  )
                                : null,
                    body: TabBarView(
                      children: [
                        _ProductsTab(storeId: storeId),
                        _CategoriesTab(storeId: storeId),
                        _OffersTab(storeId: storeId),
                        _BoostRequestsTab(storeId: storeId),
                        _OrdersTab(storeId: storeId),
                        StoreTendersTab(storeId: storeId, storeName: 'متجري'),
                        StoreOwnerTenderCommissionsTab(storeId: storeId),
                        _CommissionsTab(storeId: storeId),
                        ReviewsSection(
                          targetId: storeId,
                          targetType: 'store',
                          title: 'مراجعات متجري',
                          canReply: true,
                          canDeleteReviews: true,
                        ),
                        StoreOwnerAnalyticsSection(storeId: storeId),
                        _StoreSettingsTab(storeId: storeId),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
          },
        );
      },
    );
  }
}

// ——— Tab 1: Products ———

class _ProductsTab extends StatefulWidget {
  const _ProductsTab({required this.storeId});

  final String storeId;

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  late Future<OwnerDocList> _future;

  @override
  void initState() {
    super.initState();
    _future = StoreOwnerRepository.fetchProducts(widget.storeId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = StoreOwnerRepository.fetchProducts(widget.storeId);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final storeId = widget.storeId;
    return FutureBuilder<List<OwnerEntityDoc>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: 4,
            itemBuilder: (_, index) => _buildShimmerCard(),
          );
        }
        final docs = snap.data ?? <OwnerEntityDoc>[];
        if (docs.isEmpty) {
          return _buildEmptyState('لا منتجات بعد.', Icons.inventory_2_outlined);
        }
        return RefreshIndicator(
          color: AppColors.primaryOrange,
          onRefresh: _reload,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final m = d.data();
              final img = webSafeFirstProductImage(m['image_urls'] ?? m['imageUrls'] ?? m['images']);
              // نفس منطق السعر المعروض للزائر (مع نافذة خصم اختيارية من Firestore).
              final pricing = StoreProductDiscountView.fromProductMap(m);
              final price = pricing.basePrice;
              final discountPrice = pricing.hasActiveDiscount ? pricing.effectivePrice : null;
              final hasDiscount = pricing.hasActiveDiscount;
              final avail = m['isAvailable'] != false;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: img.isEmpty
                        ? Container(
                            width: 64,
                            height: 64,
                            color: AppColors.lightOrange,
                            child: Icon(Icons.image_outlined, color: AppColors.primaryOrange.withValues(alpha: 0.5)),
                          )
                        : AmmarCachedImage(imageUrl: img, width: 64, height: 64, fit: BoxFit.cover, productTileStyle: true),
                  ),
                  title: Text(
                    m['name']?.toString() ?? (throw StateError('NULL_RESPONSE')),
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasDiscount && discountPrice != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                '${((1 - (discountPrice / price)) * 100).toStringAsFixed(0)}% خصم',
                                style: GoogleFonts.tajawal(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$price د',
                              style: GoogleFonts.tajawal(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${discountPrice.toStringAsFixed(2)} د',
                          style: GoogleFonts.tajawal(color: AppColors.darkOrange, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ] else
                        Text(
                          '${price.toStringAsFixed(2)} د',
                          style: GoogleFonts.tajawal(color: AppColors.darkOrange, fontWeight: FontWeight.w700),
                        ),
                      Text(
                        avail ? 'متوفر' : 'غير متوفر',
                        style: GoogleFonts.tajawal(fontSize: 12, color: avail ? AppColors.success : AppColors.error),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: AppColors.navy),
                        onPressed: () => _openProductSheet(context, storeId: storeId, existingId: d.id, data: m),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () => _confirmDeleteProduct(context, storeId, d.id),
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
}

Widget _buildShimmerCard() {
  return Shimmer.fromColors(
    baseColor: Colors.grey.shade300,
    highlightColor: Colors.grey.shade100,
    child: Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
    ),
  );
}

Widget _buildEmptyState(String message, IconData icon) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(message, style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 16)),
      ],
    ),
  );
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(title, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(body, textAlign: TextAlign.right, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteProduct(BuildContext context, String storeId, String productId) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('حذف المنتج؟', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('حذف', style: GoogleFonts.tajawal(color: Colors.white)),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await StoreOwnerRepository.deleteProduct(storeId, productId);
  }
}

Future<void> _openProductSheet(
  BuildContext context, {
  required String storeId,
  String? existingId,
  Map<String, dynamic>? data,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _ProductFormSheet(
      storeId: storeId,
      productId: existingId,
      initial: data,
    ),
  );
}

class _ProductFormSheet extends StatefulWidget {
  const _ProductFormSheet({required this.storeId, this.productId, this.initial});

  final String storeId;
  final String? productId;
  final Map<String, dynamic>? initial;

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late final TextEditingController _disc;
  late final TextEditingController _stock;
  String? _category;
  bool _avail = true;
  final List<Uint8List> _newImages = <Uint8List>[];
  List<String> _existingUrls = <String>[];
  bool _saving = false;
  bool _hasVariants = false;
  final List<_VariantInput> _variants = <_VariantInput>[];

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _name = TextEditingController(text: d?['name']?.toString() ?? (throw StateError('NULL_RESPONSE')));
    _desc =
        TextEditingController(text: d?['description']?.toString() ?? (throw StateError('NULL_RESPONSE')));
    _price = TextEditingController(text: (d != null && d['price'] != null) ? '${d['price']}' : '');
    _disc = TextEditingController(
      text: (d != null && d['discountPrice'] != null) ? '${d['discountPrice']}' : '',
    );
    _stock = TextEditingController(text: (d != null && d['stock'] != null) ? '${d['stock']}' : '0');
    _avail = d?['isAvailable'] != false;
    _hasVariants = d?['hasVariants'] == true;
    _category = d?['shelfCategory']?.toString();
    final imgs = d?['image_urls'] ?? d?['imageUrls'] ?? d?['images'];
    if (imgs is List) {
      _existingUrls = imgs.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } else if (imgs is String && imgs.trim().isNotEmpty) {
      _existingUrls = [imgs.trim()];
    }
    final rawVariants = d?['variants'];
    if (rawVariants is List) {
      for (final v in rawVariants) {
        if (v is! Map) continue;
        final map = Map<String, dynamic>.from(v);
        _variants.add(
          _VariantInput(
            optionType: map['optionType']?.toString() ?? map['option_type']?.toString() ?? 'size',
            optionValue: map['optionValue']?.toString() ??
                map['option_value']?.toString() ??
                (throw StateError('NULL_RESPONSE')),
            price: map['price']?.toString() ?? (throw StateError('NULL_RESPONSE')),
            stock: map['stock']?.toString() ?? '0',
            isDefault: map['isDefault'] == true || map['is_default'] == true,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _disc.dispose();
    _stock.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  void _addVariant() {
    setState(() {
      _variants.add(_VariantInput(optionType: 'size', optionValue: '', price: '', stock: '0'));
    });
  }

  List<Map<String, dynamic>> _variantPayloads() {
    return _variants
        .map((v) => {
              'optionType': v.optionType,
              'optionValue': v.optionValue.text.trim(),
              'price': double.tryParse(v.price.text.replaceAll(',', '.')) ??
                  (throw StateError('INVALID_NUMERIC_DATA')),
              'stock':
                  int.tryParse(v.stock.text.trim()) ?? (throw StateError('INVALID_NUMERIC_DATA')),
              'isDefault': v.isDefault,
              'options': [
                {'optionType': v.optionType, 'optionValue': v.optionValue.text.trim()},
              ],
            })
        .toList();
  }

  Future<void> _pickImages() async {
    final max = StoreOwnerRepository.maxProductImages;
    final left = max - (_existingUrls.length + _newImages.length);
    if (left <= 0) return;
    final picker = ImagePicker();
    final list = await picker.pickMultiImage(
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (list.isEmpty) return;
    for (final x in list.take(left)) {
      final b = await x.readAsBytes();
      setState(() => _newImages.add(b));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? (throw StateError('NULL_RESPONSE')))) return;
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll(',', '.')) ??
        (throw StateError('INVALID_NUMERIC_DATA'));
    final discText = _disc.text.trim();
    final disc = discText.isEmpty ? null : double.tryParse(discText.replaceAll(',', '.'));
    final stock = int.tryParse(_stock.text.trim()) ?? (throw StateError('INVALID_NUMERIC_DATA'));
    if (_hasVariants) {
      if (_variants.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('أضف متغيرًا واحدًا على الأقل للمنتج', style: GoogleFonts.tajawal())),
        );
        return;
      }
      for (final v in _variants) {
        if (v.optionValue.text.trim().isEmpty ||
            (double.tryParse(v.price.text.replaceAll(',', '.')) ?? -1) < 0 ||
            (int.tryParse(v.stock.text.trim()) ?? -1) < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تأكد من تعبئة بيانات المتغيرات بشكل صحيح', style: GoogleFonts.tajawal())),
          );
          return;
        }
      }
    }
    if (_category == null || _category!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('اختر التصنيف', style: GoogleFonts.tajawal())),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final resolvedProductId = widget.productId != null && widget.productId!.trim().isNotEmpty
          ? widget.productId!
          : StoreOwnerRepository.newStoreProductDocumentId(widget.storeId);
      if (resolvedProductId.trim().isEmpty) {
        throw StateError('INVALID_ID');
      }
      debugPrint('[StoreOwnerIsolation] upsert product → stores/${widget.storeId}/products/$resolvedProductId');
      final urls = List<String>.from(_existingUrls);
      if (_newImages.isNotEmpty) {
        final up = await StoreOwnerRepository.uploadProductImages(
          storeId: widget.storeId,
          productId: resolvedProductId,
          bytesList: _newImages,
        );
        urls.addAll(up);
      }
      final max = StoreOwnerRepository.maxProductImages;
      if (urls.length > max) urls.removeRange(max, urls.length);

      await StoreOwnerRepository.upsertProduct(
        storeId: widget.storeId,
        productId: resolvedProductId,
        name: name,
        description: _desc.text.trim(),
        price: price,
        discountPrice: disc,
        imageUrls: urls.take(max).toList(),
        shelfCategory: _category!,
        stock: stock,
        isAvailable: _avail,
        hasVariants: _hasVariants,
        variants: _hasVariants ? _variantPayloads() : const <Map<String, dynamic>>[],
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.productId == null ? 'إضافة منتج' : 'تعديل منتج', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textAlign: TextAlign.right,
                decoration: InputDecoration(labelText: 'اسم المنتج *', labelStyle: GoogleFonts.tajawal()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              TextFormField(
                controller: _desc,
                minLines: 2,
                maxLines: 4,
                textAlign: TextAlign.right,
                decoration: InputDecoration(labelText: 'الوصف', labelStyle: GoogleFonts.tajawal()),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'السعر الأصلي (د) *',
                        labelStyle: GoogleFonts.tajawal(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) {
                        final input = v ?? (throw StateError('NULL_RESPONSE'));
                        if (input.trim().isEmpty) {
                          return 'يرجى إدخال السعر';
                        }
                        if (double.tryParse(
                              input.replaceAll(',', '.'),
                            ) ==
                            null) {
                          return 'أدخل قيمة رقمية صحيحة';
                        }
                        return (null);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _disc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'سعر العرض (د) - اختياري',
                        helperText: 'اتركه فارغاً إذا لا يوجد خصم',
                        labelStyle: GoogleFonts.tajawal(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) {
                        final t = (v ?? (throw StateError('NULL_RESPONSE'))).trim();
                        if (t.isEmpty) return (null);
                        final dv = double.tryParse(t.replaceAll(',', '.'));
                        final pv = double.tryParse(_price.text.trim().replaceAll(',', '.'));
                        if (dv == null) return 'أدخل قيمة رقمية صحيحة';
                        if (dv <= 0) return 'سعر العرض يجب أن يكون أكبر من 0';
                        if (pv != null && dv >= pv) return 'سعر العرض يجب أن يكون أقل من السعر الأصلي';
                        return (null);
                      },
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _stock,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'المخزون', labelStyle: GoogleFonts.tajawal()),
              ),
              SwitchListTile(
                title: Text('متاح للبيع', style: GoogleFonts.tajawal()),
                value: _avail,
                activeThumbColor: AppColors.primaryOrange,
                onChanged: (v) => setState(() => _avail = v),
              ),
              SwitchListTile(
                title: Text('هذا المنتج يحتوي متغيرات', style: GoogleFonts.tajawal()),
                value: _hasVariants,
                activeThumbColor: AppColors.primaryOrange,
                onChanged: (v) => setState(() => _hasVariants = v),
              ),
              if (_hasVariants) ...[
                Row(
                  children: [
                    Text('المتغيرات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addVariant,
                      icon: const Icon(Icons.add_circle_outline),
                      label: Text('إضافة متغير', style: GoogleFonts.tajawal()),
                    ),
                  ],
                ),
                ..._variants.asMap().entries.map((entry) {
                  final i = entry.key;
                  final v = entry.value;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  // ignore: deprecated_member_use
                                  value: v.optionType,
                                  items: const [
                                    DropdownMenuItem(value: 'size', child: Text('Size')),
                                    DropdownMenuItem(value: 'color', child: Text('Color')),
                                    DropdownMenuItem(value: 'weight', child: Text('Weight')),
                                    DropdownMenuItem(value: 'dimension', child: Text('Dimension')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => v.optionType = val);
                                  },
                                  decoration: InputDecoration(labelText: 'نوع الخيار', labelStyle: GoogleFonts.tajawal()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: v.optionValue,
                                  decoration: InputDecoration(labelText: 'قيمة الخيار', labelStyle: GoogleFonts.tajawal()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: v.price,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(labelText: 'السعر', labelStyle: GoogleFonts.tajawal()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: v.stock,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(labelText: 'المخزون', labelStyle: GoogleFonts.tajawal()),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Checkbox(
                                value: v.isDefault,
                                onChanged: (val) {
                                  setState(() {
                                    for (final x in _variants) {
                                      x.isDefault = false;
                                    }
                                    v.isDefault = val == true;
                                  });
                                },
                              ),
                              Text('افتراضي', style: GoogleFonts.tajawal()),
                              const Spacer(),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _variants.removeAt(i).dispose();
                                  });
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              FutureBuilder<List<OwnerEntityDoc>>(
                future: StoreOwnerRepository.fetchCategories(widget.storeId),
                builder: (context, snap) {
                  final cats = snap.data ?? <OwnerEntityDoc>[];
                  final names = cats
                      .map((c) => c.data()['name']?.toString() ?? (throw StateError('NULL_RESPONSE')))
                      .where((s) => s.isNotEmpty)
                      .toList();
                  if (names.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'أضف تصنيفاً من تبويب «أقسامي» أولاً.',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(color: AppColors.error, fontSize: 13),
                      ),
                    );
                  }
                  final effective = (_category != null && names.contains(_category)) ? _category! : names.first;
                  return DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: effective,
                    decoration: InputDecoration(labelText: 'التصنيف *', labelStyle: GoogleFonts.tajawal()),
                    items: names
                        .map((n) => DropdownMenuItem(value: n, child: Text(n, style: GoogleFonts.tajawal(), textAlign: TextAlign.right)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _category = v);
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: (_existingUrls.length + _newImages.length) >= StoreOwnerRepository.maxProductImages
                      ? null
                      : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.primaryOrange),
                  label: Text(
                    'صور (حد أقصى ${StoreOwnerRepository.maxProductImages})',
                    style: GoogleFonts.tajawal(color: AppColors.primaryOrange),
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  ..._existingUrls.map(
                    (u) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AmmarCachedImage(
                            imageUrl: webSafeImageUrl(u),
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            productTileStyle: true,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _existingUrls.remove(u)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...List.generate(_newImages.length, (i) {
                    final b = _newImages[i];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(b, width: 72, height: 72, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _newImages.removeAt(i)),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _saving
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('حفظ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ——— Tab 2: Categories ———

class _CategoriesTab extends StatefulWidget {
  const _CategoriesTab({required this.storeId});

  final String storeId;

  @override
  State<_CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<_CategoriesTab> {
  bool _loadingHybrid = false;
  String? _hybridMode;
  List<Map<String, dynamic>> _hybridCategories = <Map<String, dynamic>>[];

  bool get _useHybrid => StoreOwnerRepository.enableHybridStoreBuilder;

  @override
  void initState() {
    super.initState();
    if (_useHybrid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHybrid());
    }
  }

  Future<void> _loadHybrid() async {
    if (!_useHybrid) return;
    setState(() => _loadingHybrid = true);
    await Future<void>.sync(() async {
      var payload = await StoreOwnerRepository.getHybridStoreBuilder(widget.storeId);
      payload ??= await StoreOwnerRepository.bootstrapHybridStoreBuilder(
        storeId: widget.storeId,
      );
      final store = payload?['store'];
      final categoriesRaw = payload?['categories'];
      final categories = <Map<String, dynamic>>[];
      if (categoriesRaw is List) {
        for (final e in categoriesRaw) {
          if (e is Map) {
            categories.add(Map<String, dynamic>.from(e));
          }
        }
      }
      categories.sort(
        (a, b) => ((a['sortOrder'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA')))
            .compareTo((b['sortOrder'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA'))),
      );
      if (!mounted) return;
      setState(() {
        _hybridMode = store is Map ? store['mode']?.toString() : null;
        _hybridCategories = categories;
      });
    }).onError((error, stackTrace) {
      debugPrint('[HybridStoreBuilder] categories load failed: $error');
      BackendFallbackLogger.logBackendFallbackTriggered(
        flow: 'store_builder_hybrid_load',
        reason: error.runtimeType.toString(),
        extra: {'error': error.toString(), 'storeId': widget.storeId},
      );
    }).whenComplete(() {
      if (mounted) setState(() => _loadingHybrid = false);
    });
  }

  Future<void> _moveHybridCategory(int index, int delta) async {
    final next = index + delta;
    if (next < 0 || next >= _hybridCategories.length) return;
    final cloned = [..._hybridCategories];
    final item = cloned.removeAt(index);
    cloned.insert(next, item);
    setState(() => _hybridCategories = cloned);
    await StoreOwnerRepository.reorderHybridCategories(
        storeId: widget.storeId,
        items: [
          for (var i = 0; i < cloned.length; i++)
            {
              'id': cloned[i]['id']?.toString() ?? (throw StateError('NULL_RESPONSE')),
              'sortOrder': i + 1,
            },
        ],
      ).onError((error, stackTrace) {
      debugPrint('[HybridStoreBuilder] reorder failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر إعادة الترتيب', style: GoogleFonts.tajawal())),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_useHybrid) {
      if (_loadingHybrid && _hybridCategories.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hybridMode != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _hybridMode == 'MANUAL'
                    ? 'الوضع اليدوي: تحكم كامل بالأقسام'
                    : 'الوضع الذكي: تحسينات AI مع إمكانية التعديل',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: AppColors.darkOrange),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _hybridCategories.length,
              itemBuilder: (context, i) {
                final c = _hybridCategories[i];
                final id = c['id']?.toString() ?? (throw StateError('NULL_RESPONSE'));
                final name = c['name']?.toString() ?? (throw StateError('NULL_RESPONSE'));
                final imageUrl = webSafeImageUrl(
                  c['imageUrl']?.toString() ??
                      c['image_url']?.toString() ??
                      (throw StateError('NULL_RESPONSE')),
                );
                return Card(
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageUrl.isEmpty
                          ? Container(
                              width: 52,
                              height: 52,
                              color: AppColors.lightOrange,
                              child: Icon(Icons.category_outlined, color: AppColors.primaryOrange.withValues(alpha: 0.6)),
                            )
                          : AmmarCachedImage(
                              imageUrl: imageUrl,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              productTileStyle: true,
                            ),
                    ),
                    title: Text(name, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          onPressed: i > 0 ? () => _moveHybridCategory(i, -1) : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          onPressed: i < _hybridCategories.length - 1 ? () => _moveHybridCategory(i, 1) : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: AppColors.navy),
                          onPressed: () => _openEditCategorySheet(
                            context,
                            storeId: widget.storeId,
                            docId: id,
                            initialName: name,
                            initialImageUrl: imageUrl,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          onPressed: () async {
                            await StoreOwnerRepository.deleteHybridCategory(storeId: widget.storeId, categoryId: id);
                            await _loadHybrid();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('التصنيفات المحفوظة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        Expanded(
          flex: 2,
          child: FutureBuilder<List<OwnerEntityDoc>>(
            future: StoreOwnerRepository.fetchCategories(widget.storeId),
            builder: (context, snap) {
              final docs = snap.data ?? <OwnerEntityDoc>[];
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final n = d.data()['name']?.toString() ?? (throw StateError('NULL_RESPONSE'));
                  final imgUrl = webSafeImageUrl(
                    d.data()['imageUrl']?.toString() ?? (throw StateError('NULL_RESPONSE')),
                  );
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: imgUrl.isEmpty
                            ? Container(
                                width: 52,
                                height: 52,
                                color: AppColors.lightOrange,
                                child: Icon(Icons.category_outlined, color: AppColors.primaryOrange.withValues(alpha: 0.6)),
                              )
                            : AmmarCachedImage(
                                imageUrl: imgUrl,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                productTileStyle: true,
                              ),
                      ),
                      title: Text(n, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: AppColors.navy),
                            onPressed: () => _openEditCategorySheet(
                              context,
                              storeId: widget.storeId,
                              docId: d.id,
                              initialName: n,
                              initialImageUrl: d.data()['imageUrl']?.toString(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.error),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('حذف التصنيف؟', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                  content: Text(
                                    'سيتم نقل منتجات هذا القسم إلى «عام» ثم حذف التصنيف.',
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.tajawal(),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text('حذف', style: GoogleFonts.tajawal(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await StoreOwnerRepository.deleteCategoryAndReassignProducts(
                                  storeId: widget.storeId,
                                  categoryDocId: d.id,
                                  categoryName: n,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('تصنيفات مستخرجة من المنتجات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        Expanded(
          flex: 1,
          child: FutureBuilder<Set<String>>(
            future: StoreOwnerRepository.fetchDistinctProductCategoryNames(widget.storeId),
            builder: (context, snap) {
              final set = snap.data ?? {};
              if (set.isEmpty) {
                return Center(child: Text('لا توجد بعد.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
              }
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: set.map((e) => Chip(label: Text(e, style: GoogleFonts.tajawal()))).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VariantInput {
  _VariantInput({
    required this.optionType,
    required String optionValue,
    required String price,
    required String stock,
    this.isDefault = false,
  })  : optionValue = TextEditingController(text: optionValue),
        price = TextEditingController(text: price),
        stock = TextEditingController(text: stock);

  String optionType;
  final TextEditingController optionValue;
  final TextEditingController price;
  final TextEditingController stock;
  bool isDefault;

  void dispose() {
    optionValue.dispose();
    price.dispose();
    stock.dispose();
  }
}

Future<void> _openCategorySheet(BuildContext context, {required String storeId}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _AddCategorySheet(storeId: storeId),
  );
}

Future<void> _openEditCategorySheet(
  BuildContext context, {
  required String storeId,
  required String docId,
  required String initialName,
  String? initialImageUrl,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _EditCategorySheet(
      storeId: storeId,
      docId: docId,
      initialName: initialName,
      initialImageUrl: initialImageUrl,
    ),
  );
}

class _AddCategorySheet extends StatefulWidget {
  const _AddCategorySheet({required this.storeId});

  final String storeId;

  @override
  State<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<_AddCategorySheet> {
  final _ctrl = TextEditingController();
  Uint8List? _imageBytes;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تصنيف جديد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(hintText: 'اسم التصنيف *', hintStyle: GoogleFonts.tajawal()),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final picker = ImagePicker();
                        final x = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                          maxWidth: 1200,
                          maxHeight: 1200,
                        );
                        if (x == null) return;
                        final b = await x.readAsBytes();
                        setState(() => _imageBytes = b);
                      },
                icon: const Icon(Icons.image_outlined, color: AppColors.primaryOrange),
                label: Text(_imageBytes == null ? 'صورة التصنيف (اختياري)' : 'تغيير الصورة', style: GoogleFonts.tajawal()),
              ),
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_imageBytes!, height: 100, fit: BoxFit.cover),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final name = _ctrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('أدخل اسم التصنيف', style: GoogleFonts.tajawal())),
                        );
                        return;
                      }
                      setState(() => _busy = true);
                      try {
                        if (StoreOwnerRepository.enableHybridStoreBuilder) {
                          await StoreOwnerRepository.addHybridCategory(
                            storeId: widget.storeId,
                            name: name,
                            imageUrl: '',
                          );
                        } else {
                          await StoreOwnerRepository.addCategoryWithImage(
                            storeId: widget.storeId,
                            name: name,
                            imageBytes: _imageBytes,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('إضافة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditCategorySheet extends StatefulWidget {
  const _EditCategorySheet({
    required this.storeId,
    required this.docId,
    required this.initialName,
    this.initialImageUrl,
  });

  final String storeId;
  final String docId;
  final String initialName;
  final String? initialImageUrl;

  @override
  State<_EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends State<_EditCategorySheet> {
  late final TextEditingController _ctrl;
  Uint8List? _newImageBytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = webSafeImageUrl(widget.initialImageUrl ?? (throw StateError('NULL_RESPONSE')));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تعديل التصنيف', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              textAlign: TextAlign.right,
              decoration: InputDecoration(hintText: 'اسم التصنيف *', hintStyle: GoogleFonts.tajawal()),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final picker = ImagePicker();
                        final x = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                          maxWidth: 1200,
                          maxHeight: 1200,
                        );
                        if (x == null) return;
                        final b = await x.readAsBytes();
                        setState(() => _newImageBytes = b);
                      },
                icon: const Icon(Icons.image_outlined, color: AppColors.primaryOrange),
                label: Text(_newImageBytes == null ? 'تغيير صورة التصنيف' : 'استبدال الصورة', style: GoogleFonts.tajawal()),
              ),
            ),
            const SizedBox(height: 8),
            if (_newImageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_newImageBytes!, height: 100, fit: BoxFit.cover),
              )
            else if (existing.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AmmarCachedImage(imageUrl: existing, height: 100, width: double.infinity, fit: BoxFit.cover, productTileStyle: true),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final name = _ctrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('أدخل اسم التصنيف', style: GoogleFonts.tajawal())),
                        );
                        return;
                      }
                      setState(() => _busy = true);
                      try {
                        if (StoreOwnerRepository.enableHybridStoreBuilder) {
                          await StoreOwnerRepository.updateHybridCategory(
                            storeId: widget.storeId,
                            categoryId: widget.docId,
                            name: name,
                            imageUrl: null,
                          );
                        } else {
                          String? imageUrl;
                          if (_newImageBytes != null && _newImageBytes!.isNotEmpty) {
                            imageUrl = await StoreOwnerRepository.uploadCategoryImage(
                              storeId: widget.storeId,
                              categoryDocId: widget.docId,
                              bytes: _newImageBytes!,
                            );
                          }
                          await StoreOwnerRepository.updateCategory(
                            storeId: widget.storeId,
                            docId: widget.docId,
                            name: name,
                            imageUrl: imageUrl,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('حفظ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

// ——— Tab 3: Offers ———

class _OffersTab extends StatelessWidget {
  const _OffersTab({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<OwnerEntityDoc>>(
      future: StoreOwnerRepository.fetchOffers(storeId),
      builder: (context, snap) {
        // كان الخطأ يُعرض كقائمة فارغة؛ نعرض رسالة واضحة ونُسجّل السبب للتصحيح.
        if (snap.hasError) {
          debugPrint('[StoreOwnerDashboard._OffersTab] watchOffers error: ${snap.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'حدث خطأ في تحميل عروض المتجر. يرجى المحاولة لاحقاً.',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(color: AppColors.error),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
        }
        final docs = snap.data ?? <OwnerEntityDoc>[];
        if (docs.isEmpty) {
          return Center(child: Text('لا عروض بعد.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final img =
                webSafeImageUrl(m['imageUrl']?.toString() ?? (throw StateError('NULL_RESPONSE')));
            final until = m['validUntil'];
            var untilStr = _storeOwnerFormatDateShort(until);
            if (untilStr == '—' && until is String && until.isNotEmpty) {
              final p = DateTime.tryParse(until);
              if (p != null) untilStr = p.toString().split(' ').first;
            }
            return Card(
              child: ListTile(
                leading: img.isEmpty
                    ? const Icon(Icons.local_offer_outlined)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AmmarCachedImage(imageUrl: img, width: 56, height: 56, fit: BoxFit.cover, productTileStyle: true),
                      ),
                title: Text(
                  m['title']?.toString() ?? (throw StateError('NULL_RESPONSE')),
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${m['discountPercent']?.toString() ?? (throw StateError('NULL_RESPONSE'))}% · حتى $untilStr',
                  style: GoogleFonts.tajawal(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('حذف العرض؟', style: GoogleFonts.tajawal()),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.tajawal())),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('حذف', style: GoogleFonts.tajawal())),
                        ],
                      ),
                    );
                    if (ok == true) await StoreOwnerRepository.deleteOffer(storeId, d.id);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _openOfferSheet(BuildContext context, {required String storeId}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => _OfferFormSheet(storeId: storeId),
  );
}

class _OfferFormSheet extends StatefulWidget {
  const _OfferFormSheet({required this.storeId});

  final String storeId;

  @override
  State<_OfferFormSheet> createState() => _OfferFormSheetState();
}

class _OfferFormSheetState extends State<_OfferFormSheet> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  double _pct = 20;
  DateTime _until = DateTime.now().add(const Duration(days: 7));
  Uint8List? _image;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => _image = b);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('اختر صورة للعرض', style: GoogleFonts.tajawal())));
      return;
    }
    setState(() => _saving = true);
    try {
      final url = await StoreOwnerRepository.uploadOfferImage(storeId: widget.storeId, bytes: _image!);
      await StoreOwnerRepository.addOffer(
        storeId: widget.storeId,
        title: _title.text.trim(),
        description: _desc.text.trim(),
        discountPercent: _pct,
        validUntil: _until,
        imageUrl: url,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('عرض جديد', style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
            TextField(controller: _title, textAlign: TextAlign.right, decoration: InputDecoration(labelText: 'العنوان', labelStyle: GoogleFonts.tajawal())),
            TextField(controller: _desc, minLines: 2, maxLines: 4, textAlign: TextAlign.right, decoration: InputDecoration(labelText: 'الوصف', labelStyle: GoogleFonts.tajawal())),
            Text('نسبة الخصم: ${_pct.round()}%', style: GoogleFonts.tajawal()),
            Slider(
              value: _pct,
              min: 5,
              max: 80,
              divisions: 15,
              label: '${_pct.round()}%',
              activeColor: AppColors.primaryOrange,
              onChanged: (v) => setState(() => _pct = v),
            ),
            ListTile(
              title: Text('صالح حتى', style: GoogleFonts.tajawal()),
              subtitle: Text(_until.toString().split(' ').first, style: GoogleFonts.tajawal()),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today_rounded, color: AppColors.primaryOrange),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    initialDate: _until,
                  );
                  if (d != null) setState(() => _until = d);
                },
              ),
            ),
            TextButton.icon(onPressed: _pick, icon: const Icon(Icons.image_outlined), label: Text('صورة العرض', style: GoogleFonts.tajawal())),
            if (_image != null) ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_image!, height: 120, fit: BoxFit.cover)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange),
              child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('حفظ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

// ——— Helpers: تفاصيل الطلب (هاتف، عنوان، خريطة، صور) ———

String _orderPhoneFromMap(Map<String, dynamic> m) {
  final billing = m['billing'];
  if (billing is Map) {
    final p = billing['phone']?.toString().trim();
    if (p != null && p.isNotEmpty) return p;
  }
  return m['customerPhone']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
}

String _orderAddressFromMap(Map<String, dynamic> m) {
  final da = m['deliveryAddress']?.toString().trim();
  if (da != null && da.isNotEmpty) return da;
  final billing = m['billing'];
  if (billing is Map) {
    final raw = [
      billing['address_1']?.toString().trim(),
      billing['city']?.toString().trim(),
      billing['country']?.toString().trim(),
    ];
    final parts = <String>[
      for (final s in raw)
        if (s != null && s.isNotEmpty) s,
    ];
    if (parts.isNotEmpty) return parts.join(', ');
  }
  return '';
}

(double lat, double lng)? _deliveryLatLng(Map<String, dynamic> m) {
  final loc = m['deliveryLocation'];
  if (loc == null) throw StateError('NULL_RESPONSE');
  if (loc is Map) {
    final la = loc['latitude'];
    final ln = loc['longitude'];
    if (la is num && ln is num) return (la.toDouble(), ln.toDouble());
  }
  if (loc is Map) {
    final map = Map<String, dynamic>.from(loc);
    final latRaw = map['latitude'] ?? map['lat'];
    final lngRaw = map['longitude'] ?? map['lng'];
    final lat = latRaw is num
        ? latRaw.toDouble()
        : double.tryParse(latRaw?.toString() ?? (throw StateError('NULL_RESPONSE')));
    final lng = lngRaw is num
        ? lngRaw.toDouble()
        : double.tryParse(lngRaw?.toString() ?? (throw StateError('NULL_RESPONSE')));
    if (lat != null && lng != null) return (lat, lng);
  }
  throw StateError('NULL_RESPONSE');
}

Future<void> _openDeliveryOnMap(BuildContext context, Map<String, dynamic> m) async {
  final pair = _deliveryLatLng(m);
  if (pair == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('لا يوجد موقع محدد على الخريطة.', style: GoogleFonts.tajawal())),
    );
    return;
  }
  final (lat, lng) = pair;
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر فتح الخرائط.', style: GoogleFonts.tajawal())),
    );
  }
}

String? _firstImageFromOrderLine(Map<String, dynamic> it) {
  final raw = it['images'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  if (raw is List && raw.isNotEmpty) {
    final first = raw.first;
    if (first is String && first.trim().isNotEmpty) return first.trim();
    if (first is Map) {
      final src = first['src'] ?? first['url'];
      if (src != null && src.toString().trim().isNotEmpty) return src.toString().trim();
    }
  }
  final single = it['imageUrl'] ?? it['image'];
  if (single != null && single.toString().trim().isNotEmpty) return single.toString().trim();
  throw StateError('NULL_RESPONSE');
}

String? _orderTenderImageFromMap(Map<String, dynamic> m) {
  final directTender = m['tenderImageUrl']?.toString().trim();
  if (directTender != null && directTender.isNotEmpty) return directTender;
  final isTenderOrder = m['isTender'] == true;
  if (isTenderOrder) {
    final directImage = m['imageUrl']?.toString().trim();
    if (directImage != null && directImage.isNotEmpty) return directImage;
  }
  final items = m['items'];
  if (items is List) {
    for (final raw in items) {
      if (raw is! Map) continue;
      final it = Map<String, dynamic>.from(raw);
      if (it['isTender'] == true) {
        final itemTender = it['tenderImageUrl']?.toString().trim();
        if (itemTender != null && itemTender.isNotEmpty) return itemTender;
        final itemImage = _firstImageFromOrderLine(it);
        if (itemImage != null && itemImage.isNotEmpty) return itemImage;
      }
    }
  }
  throw StateError('NULL_RESPONSE');
}

Widget? _orderTenderImageSection(BuildContext context, Map<String, dynamic> m) {
  final tenderImageUrl = _orderTenderImageFromMap(m);
  if (tenderImageUrl == null || tenderImageUrl.isEmpty) throw StateError('NULL_RESPONSE');
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.gavel, color: Color(0xFFFF6B00), size: 18),
            const SizedBox(width: 6),
            Text(
              'صورة المناقصة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: const Color(0xFFFF6B00)),
            ),
            const SizedBox(width: 8),
            Text(
              '(اضغط للتكبير)',
              style: GoogleFonts.cairo(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
      GestureDetector(
        onTap: () => openImageViewer(context, imageUrl: tenderImageUrl, title: 'صورة المناقصة'),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF6B00).withValues(alpha: 0.3), width: 2),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AmmarCachedImage(
                  imageUrl: tenderImageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  productTileStyle: true,
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.open_in_full, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
    ],
  );
}

Widget _orderContactRow(Map<String, dynamic> m) {
  final phone = _orderPhoneFromMap(m);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.phone_in_talk_rounded, size: 20, color: AppColors.primaryOrange),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('هاتف العميل', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
            SelectableText(
              phone.isEmpty ? '—' : phone,
              textAlign: TextAlign.right,
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _orderLocationRow(BuildContext context, Map<String, dynamic> m) {
  final addr = _orderAddressFromMap(m);
  final hasMap = _deliveryLatLng(m) != null;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_rounded, size: 20, color: AppColors.primaryOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('عنوان التوصيل', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
                Text(
                  addr.isEmpty ? '—' : addr,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
      if (hasMap)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _openDeliveryOnMap(context, m),
            icon: const Icon(Icons.map_rounded, size: 20, color: AppColors.primaryOrange),
            label: Text('فتح الموقع على الخريطة', style: GoogleFonts.tajawal(color: AppColors.primaryOrange, fontWeight: FontWeight.w600)),
          ),
        ),
    ],
  );
}

Widget? _orderLineThumb(Map<String, dynamic> it) {
  final url = _firstImageFromOrderLine(it);
  if (url == null || url.isEmpty) {
    return const SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFF0F0F0), borderRadius: BorderRadius.all(Radius.circular(8))),
        child: Icon(Icons.image_not_supported_outlined, size: 22, color: Colors.black26),
      ),
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: AmmarCachedImage(
      imageUrl: url,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      productTileStyle: true,
    ),
  );
}

// ——— Tab: المستحقات (عمولات) ———

class _CommissionsTab extends StatelessWidget {
  const _CommissionsTab({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoreCommissionView>(
      future: StoreOwnerRepository.fetchStoreCommissions(storeId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('تعذر تحميل المستحقات: ${snap.error}', style: GoogleFonts.tajawal()));
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
        }
        final v = snap.data;
        if (v == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
        }
        final totalCommission = v.totalCommission;
        final totalPaid = v.totalPaid;
        final balance = v.balance;
        final orderDocs = v.orderDocs;

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('ملخص المستحقات', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _commissionSummaryTile('إجمالي العمولة المستحقة', '${totalCommission.toStringAsFixed(3)} د.أ', Colors.blue.shade700)),
                            const SizedBox(width: 8),
                            Expanded(child: _commissionSummaryTile('إجمالي المدفوع', '${totalPaid.toStringAsFixed(3)} د.أ', Colors.green.shade700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _commissionSummaryTile(
                          'الرصيد المتبقي',
                          '${balance.toStringAsFixed(3)} د.أ',
                          balance > 0 ? Colors.red.shade700 : Colors.green.shade700,
                          fullWidth: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('الطلبات المسجّلة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                if (orderDocs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'لا توجد عمولات مسجّلة بعد. تُسجَّل العمولة عند وصول حالة الطلب إلى «تم التسليم».',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ...orderDocs.map((d) {
                    final o = d.data();
                    final orderTotal = (o['orderTotal'] as num?)?.toDouble() ??
                        (throw StateError('INVALID_NUMERIC_DATA'));
                    final comm = (o['commissionAmount'] as num?)?.toDouble() ??
                        (throw StateError('INVALID_NUMERIC_DATA'));
                    final hasPerOrderPayment = o.containsKey('paid') || o['paymentStatus'] != null;
                    final paid = o['paid'] == true || o['paymentStatus']?.toString().toLowerCase() == 'paid';
                    final ts = o['date'];
                    var dateStr = _storeOwnerFormatDateShort(ts);
                    if (dateStr == '—' && ts is String && ts.isNotEmpty) {
                      final p = DateTime.tryParse(ts);
                      if (p != null) dateStr = p.toString().split('.').first;
                    }
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          'طلب ${d.id.length > 10 ? '${d.id.substring(0, 8)}…' : d.id}',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.right,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('قيمة الطلب: ${orderTotal.toStringAsFixed(3)} د.أ · العمولة: ${comm.toStringAsFixed(3)} د.أ', style: GoogleFonts.tajawal(fontSize: 12)),
                            Text('تاريخ التسجيل: $dateStr', style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary)),
                            if (hasPerOrderPayment)
                              Text(
                                paid ? 'حالة الدفع: مدفوع' : 'حالة الدفع: غير مدفوع',
                                style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                        trailing: hasPerOrderPayment
                            ? Chip(
                                label: Text(
                                  paid ? 'مدفوع' : 'غير مدفوع',
                                  style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                                backgroundColor: paid ? Colors.green.shade50 : Colors.orange.shade50,
                              )
                            : Icon(Icons.receipt_long_outlined, color: AppColors.primaryOrange.withValues(alpha: 0.7)),
                      ),
                    );
                  }),
              ],
            );
      },
    );
  }

  Widget _commissionSummaryTile(String label, String value, Color color, {bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
        ],
      ),
    );
  }
}

// ——— Tab 4: Orders ———

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.storeId});

  final String storeId;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  static const int _pageSize = 20;
  final List<OwnerEntityDoc> _orders = <OwnerEntityDoc>[];
  String? _lastBackendCursor;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  Future<void> _loadInitial() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _orders.clear();
      _lastBackendCursor = null;
      _hasMore = true;
    });
    await StoreOwnerRepository.getStoreOrdersPage(
        storeId: widget.storeId,
        limit: _pageSize,
      ).then((result) {
      if (!mounted) return;
      setState(() {
        _orders.addAll(result.items);
        _lastBackendCursor = result.nextBackendCursor;
        _hasMore = result.hasMore;
      });
    }).onError((error, stackTrace) {
      debugPrint('❌ Error loading orders: $error');
      if (!mounted) return;
      setState(() => _hasError = true);
    }).whenComplete(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    if (_lastBackendCursor == null || _lastBackendCursor!.isEmpty) return;
    setState(() => _isLoadingMore = true);
    await StoreOwnerRepository.getStoreOrdersPage(
        storeId: widget.storeId,
        limit: _pageSize,
        startAfterCursor: _lastBackendCursor,
      ).then((result) {
      if (!mounted) return;
      setState(() {
        _orders.addAll(result.items);
        _lastBackendCursor = result.nextBackendCursor;
        _hasMore = result.hasMore;
      });
    }).onError((error, stackTrace) {
      debugPrint('❌ Error loading more orders: $error');
    }).whenComplete(() {
      if (mounted) setState(() => _isLoadingMore = false);
    });
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'قيد المراجعة':
        return AppColors.primaryOrange;
      case 'قيد التحضير':
        return Colors.blue.shade700;
      case 'قيد التوصيل':
        return Colors.deepPurple;
      case 'تم التسليم':
        return AppColors.success;
      case 'إلغاء':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  List<String> _allowedForwardStatuses(String current) {
    final idx = kStoreOrderStatuses.indexOf(current);
    if (idx < 0) return kStoreOrderStatuses;
    final currentIsTerminal = current == 'تم التسليم' || current == 'إلغاء';
    if (currentIsTerminal) return <String>[current];
    return kStoreOrderStatuses.sublist(idx);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('تعذر تحميل البيانات'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadInitial, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_isLoading && _orders.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 4,
        itemBuilder: (_, _) => _buildShimmerCard(),
      );
    }
    if (_orders.isEmpty) {
      return Center(child: Text('لا طلبات بعد.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      color: AppColors.primaryOrange,
      onRefresh: _loadInitial,
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
            if (_hasMore && !_isLoadingMore) _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _orders.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= _orders.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
              );
            }
            final d = _orders[i];
            final m = d.data();
            final status = m['status']?.toString() ?? kStoreOrderStatuses.first;
            final items = m['items'];
            List<Map<String, dynamic>> itemList = <Map<String, dynamic>>[];
            if (items is List) {
              for (final e in items) {
                if (e is Map<String, dynamic>) itemList.add(e);
              }
            }
            final total = m['total'];
            final totalStr = total is num ? total.toStringAsFixed(3) : (total?.toString() ?? '—');
            return Card(
              child: ExpansionTile(
                title: Text(
                  'طلب ${m['orderNumber']?.toString() ?? d.id}',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(m['customerName']?.toString() ?? '—', style: GoogleFonts.tajawal()),
                    Text('$totalStr JD', style: GoogleFonts.tajawal(color: AppColors.darkOrange, fontWeight: FontWeight.w800)),
                  ],
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status, style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(status))),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      value: kStoreOrderStatuses.contains(status) ? status : kStoreOrderStatuses.first,
                      decoration: InputDecoration(labelText: 'تحديث الحالة', labelStyle: GoogleFonts.tajawal()),
                      items: _allowedForwardStatuses(status)
                          .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.tajawal())))
                          .toList(),
                      onChanged: (status == 'تم التسليم' || status == 'إلغاء')
                          ? null
                          : (nv) async {
                        if (nv == null) return;
                        if (nv == status) return;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await StoreOwnerRepository.updateOrderStatus(widget.storeId, d.id, nv);
                          if (!context.mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text('تم تحديث حالة الطلب', style: GoogleFonts.tajawal())),
                          );
                          final customerUid = m['customerUid']?.toString().trim() ?? '';
                          if (customerUid.isNotEmpty) {
                            final storeLabel = m['storeName']?.toString().trim();
                            try {
                              await UserNotificationsRepository.notifyCustomerOrderStatusChange(
                                customerUid: customerUid,
                                orderId: d.id,
                                statusLabel: nv,
                                storeName: (storeLabel != null && storeLabel.isNotEmpty) ? storeLabel : 'المتجر',
                              );
                            } on Object catch (e) {
                              debugPrint('[StoreOwner] notifyCustomerOrderStatusChange: $e');
                            }
                          }
                          if (mounted) await _loadInitial();
                        } on Object catch (error, stackTrace) {
                          debugPrint('[StoreOwner] updateOrderStatus: $error\n$stackTrace');
                          if (context.mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('تعذّر تحديث الحالة', style: GoogleFonts.tajawal())),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _orderContactRow(m),
                        const SizedBox(height: 8),
                        _orderLocationRow(context, m),
                        const SizedBox(height: 8),
                        if (_orderTenderImageSection(context, m) != null) _orderTenderImageSection(context, m)!,
                        Text('المنتجات', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  ...itemList.map(
                    (it) => ListTile(
                      dense: true,
                      leading: _orderLineThumb(it),
                      title: Text(
                        it['name']?.toString() ?? (throw StateError('NULL_RESPONSE')),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(),
                      ),
                      subtitle: Text(
                        'الكمية: ${it['quantity'] ?? (throw StateError('INVALID_NUMERIC_DATA'))} · ${it['price'] ?? (throw StateError('NULL_RESPONSE'))}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

const List<String> kStoreDeliveryTimeOptions = <String>[
  '30-45 دقيقة',
  '45-60 دقيقة',
  '1-2 ساعة',
  '2-4 ساعات',
  'يوم-يومين',
  'حسب الطلب',
];

String _normalizeDeliveryOption(String? raw) {
  final t = raw?.trim() ?? (throw StateError('NULL_RESPONSE'));
  if (t.isNotEmpty && kStoreDeliveryTimeOptions.contains(t)) return t;
  return kStoreDeliveryTimeOptions[1];
}

class _OwnerOpeningHoursRow {
  _OwnerOpeningHoursRow()
      : openCtrl = TextEditingController(text: '09:00'),
        closeCtrl = TextEditingController(text: '21:00');

  bool closed = false;
  final TextEditingController openCtrl;
  final TextEditingController closeCtrl;

  void dispose() {
    openCtrl.dispose();
    closeCtrl.dispose();
  }
}

class _StoreSettingsTab extends StatefulWidget {
  const _StoreSettingsTab({required this.storeId});

  final String storeId;

  @override
  State<_StoreSettingsTab> createState() => _StoreSettingsTabState();
}

class _StoreSettingsTabState extends State<_StoreSettingsTab> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  String? _deliveryChoice;
  String _hybridMode = 'AI';
  bool _hybridBusy = false;
  bool _hybridLoaded = false;
  Map<String, dynamic>? _hybridSuggestions;
  final TextEditingController _shippingAmount = TextEditingController(text: '2.0');
  final TextEditingController _freeShippingThreshold = TextEditingController();
  final TextEditingController _estimatedDays = TextEditingController();
  bool _hasOwnDrivers = true;
  bool _allJordanDelivery = true;
  final Set<String> _selectedAreas = <String>{};
  bool _fieldsSeeded = false;
  Uint8List? _coverPicked;
  Uint8List? _logoPicked;
  bool _saving = false;
  late List<_OwnerOpeningHoursRow> _ohRows;
  bool _ohEnabled = false;

  @override
  void initState() {
    super.initState();
    _ohRows = List.generate(7, (_) => _OwnerOpeningHoursRow());
    _name = TextEditingController();
    _description = TextEditingController();
    _phone = TextEditingController();
    if (StoreOwnerRepository.enableHybridStoreBuilder) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHybridBuilder());
    }
  }

  @override
  void didUpdateWidget(covariant _StoreSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) {
      _fieldsSeeded = false;
      _coverPicked = null;
      _logoPicked = null;
      _deliveryChoice = null;
      _shippingAmount.text = '2.0';
      _freeShippingThreshold.clear();
      _estimatedDays.clear();
      _hasOwnDrivers = true;
      _allJordanDelivery = true;
      _selectedAreas.clear();
      for (final r in _ohRows) {
        r.dispose();
      }
      _ohRows = List.generate(7, (_) => _OwnerOpeningHoursRow());
      _ohEnabled = false;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    _shippingAmount.dispose();
    _freeShippingThreshold.dispose();
    _estimatedDays.dispose();
    for (final r in _ohRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => _coverPicked = b);
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => _logoPicked = b);
  }

  Future<void> _saveAll(Map<String, dynamic>? d) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أدخل اسم المتجر', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final delivery = _deliveryChoice ?? _normalizeDeliveryOption(d?['deliveryTime']?.toString());
    setState(() => _saving = true);
    try {
      String? coverUrl;
      String? logoUrl;
      if (_coverPicked != null && _coverPicked!.isNotEmpty) {
        coverUrl = await StoreOwnerRepository.uploadStoreCoverImage(storeId: widget.storeId, bytes: _coverPicked!);
      }
      if (_logoPicked != null && _logoPicked!.isNotEmpty) {
        logoUrl = await StoreOwnerRepository.uploadStoreLogoImage(storeId: widget.storeId, bytes: _logoPicked!);
      }
      List<String> deliveryAreas;
      if (!_hasOwnDrivers) {
        deliveryAreas = <String>[];
      } else if (_allJordanDelivery) {
        deliveryAreas = <String>['كل الأردن'];
      } else {
        deliveryAreas = _selectedAreas.toList();
      }
      await StoreOwnerRepository.updateStoreSettings(
        storeId: widget.storeId,
        name: name,
        description: _description.text.trim(),
        phone: _phone.text.trim(),
        deliveryTime: delivery,
        openingHours: _openingHoursPayload(),
        hasOwnDrivers: _hasOwnDrivers,
        deliveryFee: _hasOwnDrivers ? num.tryParse(_shippingAmount.text.trim().replaceAll(',', '.')) : 0,
        freeDeliveryMinOrder: _hasOwnDrivers && _freeShippingThreshold.text.trim().isNotEmpty
            ? num.tryParse(_freeShippingThreshold.text.trim().replaceAll(',', '.'))
            : null,
        deliveryAreas: deliveryAreas,
        coverImageUrl: coverUrl,
        logoUrl: logoUrl,
      );
      if (mounted) {
        setState(() {
          _coverPicked = null;
          _logoPicked = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ جميع التغييرات', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _openingHoursPayload() {
    final by = <String, dynamic>{};
    for (var i = 0; i < 7; i++) {
      final wd = i + 1;
      final r = _ohRows[i];
      by['$wd'] = <String, dynamic>{
        'closed': r.closed,
        'open': r.openCtrl.text.trim(),
        'close': r.closeCtrl.text.trim(),
      };
    }
    return <String, dynamic>{
      'enabled': _ohEnabled,
      'byWeekday': by,
    };
  }

  Future<void> _loadHybridBuilder() async {
    if (!StoreOwnerRepository.enableHybridStoreBuilder) return;
    await Future<void>.sync(() async {
      var payload = await StoreOwnerRepository.getHybridStoreBuilder(widget.storeId);
      payload ??= await StoreOwnerRepository.bootstrapHybridStoreBuilder(
        storeId: widget.storeId,
      );
      final store = payload?['store'];
      final mode = store is Map ? store['mode']?.toString() : null;
      if (!mounted) return;
      setState(() {
        _hybridMode = mode == 'MANUAL' ? 'MANUAL' : 'AI';
        _hybridLoaded = true;
      });
      final suggestions = await StoreOwnerRepository.getHybridSuggestions(widget.storeId);
      if (!mounted) return;
      setState(() => _hybridSuggestions = suggestions);
    }).onError((error, stackTrace) {
      debugPrint('[HybridStoreBuilder] settings load failed: $error');
    });
  }

  Future<void> _switchHybridMode(String mode) async {
    if (!StoreOwnerRepository.enableHybridStoreBuilder) return;
    setState(() => _hybridBusy = true);
    await Future<void>.sync(() async {
      await StoreOwnerRepository.setHybridStoreMode(storeId: widget.storeId, mode: mode);
      if (!mounted) return;
      setState(() => _hybridMode = mode);
      if (mode == 'AI') {
        final suggestions = await StoreOwnerRepository.getHybridSuggestions(widget.storeId);
        if (mounted) setState(() => _hybridSuggestions = suggestions);
      }
    }).onError((error, stackTrace) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر تغيير وضع المتجر', style: GoogleFonts.tajawal())),
        );
      }
    }).whenComplete(() {
      if (mounted) setState(() => _hybridBusy = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OwnerStoreSnapshot>(
      future: StoreOwnerRepository.fetchStoreSnapshot(widget.storeId),
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d != null && !_fieldsSeeded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _name.text = d['name']?.toString() ?? (throw StateError('NULL_RESPONSE'));
              _description.text = d['description']?.toString() ?? (throw StateError('NULL_RESPONSE'));
              _phone.text = d['phone']?.toString() ?? (throw StateError('NULL_RESPONSE'));
              _deliveryChoice = _normalizeDeliveryOption(d['deliveryTime']?.toString());
              final policy = ShippingPolicy.fromMap(
                d['shippingPolicy'] is Map
                    ? Map<String, dynamic>.from(d['shippingPolicy'] as Map)
                    : null,
              );
              _hasOwnDrivers = d['hasOwnDrivers'] != false && d['has_own_drivers'] != false;
              _allJordanDelivery = false;
              _selectedAreas.clear();
              final da = d['deliveryAreas'];
              if (da is List) {
                for (final e in da) {
                  final s = e?.toString().trim() ?? '';
                  if (s == 'كل الأردن') {
                    _allJordanDelivery = true;
                  } else if (s.isNotEmpty) {
                    _selectedAreas.add(s);
                  }
                }
              } else {
                _allJordanDelivery = true;
              }
              final feeRaw = d['deliveryFee'] ?? d['delivery_fee'];
              _shippingAmount.text = feeRaw != null ? feeRaw.toString() : (policy.amount?.toString() ?? '2.0');
              final minRaw = d['freeDeliveryMinOrder'] ?? d['free_delivery_min_order'];
              _freeShippingThreshold.text =
                  minRaw != null ? minRaw.toString() : (policy.freeShippingThreshold?.toString() ?? '');
              _estimatedDays.text = policy.estimatedDays?.toString() ?? '';
              final oh = StoreWeeklyHours.tryParse(d['openingHours']);
              _ohEnabled = oh?.enabled ?? false;
              for (var i = 0; i < 7; i++) {
                final wd = i + 1;
                final slot = oh?.byWeekday[wd];
                _ohRows[i].closed = slot?.closed ?? false;
                _ohRows[i].openCtrl.text = slot?.openHm ?? '09:00';
                _ohRows[i].closeCtrl.text = slot?.closeHm ?? '21:00';
              }
              _fieldsSeeded = true;
            });
          });
        }
        final coverRemote = webSafeImageUrl(d?['coverImage']?.toString() ?? '');
        final logoRemote = webSafeImageUrl(d?['logo']?.toString() ?? '');
        final deliveryVal = _deliveryChoice ?? _normalizeDeliveryOption(d?['deliveryTime']?.toString());

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('إعدادات المتجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 16),
            if (StoreOwnerRepository.enableHybridStoreBuilder) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _hybridBusy ? null : () => _switchHybridMode('AI'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _hybridMode == 'AI' ? AppColors.primaryOrange : AppColors.textSecondary,
                        ),
                      ),
                      child: Text('AI MODE', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _hybridBusy ? null : () => _switchHybridMode('MANUAL'),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: _hybridMode == 'MANUAL' ? AppColors.primaryOrange : AppColors.textSecondary,
                        ),
                      ),
                      child: Text('MANUAL MODE', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_hybridMode == 'AI')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.lightOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'AI Optimized Store',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.darkOrange),
                  ),
                ),
              if (_hybridLoaded && _hybridSuggestions != null) ...[
                const SizedBox(height: 10),
                _SuggestionCard(
                  title: 'Improve category names',
                  body: ((_hybridSuggestions!['recommendedRenames'] as List?)?.isNotEmpty ??
                          (throw StateError('NULL_RESPONSE')))
                      ? 'لديك أسماء أقسام مقترحة لتحسين المبيعات'
                      : 'لا توجد اقتراحات أسماء حالياً',
                ),
                _SuggestionCard(
                  title: 'Add featured products',
                  body: ((_hybridSuggestions!['suggestedFeaturedProducts'] as List?)?.isNotEmpty ??
                          (throw StateError('NULL_RESPONSE')))
                      ? 'يمكنك إبراز منتجات ذات تحويل أعلى'
                      : 'لا توجد اقتراحات منتجات حالياً',
                ),
                _SuggestionCard(
                  title: 'Reorder categories for more sales',
                  body: ((_hybridSuggestions!['layoutImprovements'] as List?)?.isNotEmpty ??
                          (throw StateError('NULL_RESPONSE')))
                      ? 'رتّب الأقسام حسب أولوية التحويل'
                      : 'لا توجد اقتراحات ترتيب حالياً',
                ),
              ],
              const SizedBox(height: 16),
            ],
            Text('صورة الغلاف', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _coverPicked != null
                    ? Image.memory(_coverPicked!, fit: BoxFit.cover)
                    : coverRemote.isEmpty
                        ? Container(
                            color: AppColors.lightOrange,
                            alignment: Alignment.center,
                            child: Icon(Icons.image_outlined, size: 48, color: AppColors.primaryOrange.withValues(alpha: 0.5)),
                          )
                        : AmmarCachedImage(imageUrl: coverRemote, fit: BoxFit.cover, productTileStyle: true),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickCover,
                icon: const Icon(Icons.photo_camera_back_outlined, color: AppColors.primaryOrange),
                label: Text('اختيار / تغيير الغلاف', style: GoogleFonts.tajawal()),
              ),
            ),
            const SizedBox(height: 20),
            Text('شعار المتجر', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _logoPicked != null
                      ? Image.memory(_logoPicked!, width: 88, height: 88, fit: BoxFit.cover)
                      : logoRemote.isEmpty
                          ? Container(
                              width: 88,
                              height: 88,
                              color: AppColors.lightOrange,
                              child: Icon(Icons.storefront_outlined, color: AppColors.primaryOrange.withValues(alpha: 0.5)),
                            )
                          : AmmarCachedImage(imageUrl: logoRemote, width: 88, height: 88, fit: BoxFit.cover, productTileStyle: true),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickLogo,
                    icon: const Icon(Icons.add_a_photo_outlined, color: AppColors.primaryOrange),
                    label: Text('اختيار / تغيير الشعار', style: GoogleFonts.tajawal()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'اسم المتجر',
                labelStyle: GoogleFonts.tajawal(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 2,
              maxLines: 5,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'وصف المتجر',
                labelStyle: GoogleFonts.tajawal(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                labelText: 'رقم الهاتف',
                labelStyle: GoogleFonts.tajawal(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text('أوقات العمل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('تفعيل أوقات العمل (يظهر للعميل «مغلق الآن» خارج هذه الأوقات)', style: GoogleFonts.tajawal()),
              value: _ohEnabled,
              activeThumbColor: AppColors.primaryOrange,
              onChanged: _saving ? null : (v) => setState(() => _ohEnabled = v),
            ),
            const SizedBox(height: 4),
            Text(
              'صيغة الوقت: ساعة:دقيقة (مثل 09:00 و 21:30). الأيام وفق التوقيت المحلي للجهاز.',
              style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                StoreWeeklyHours.weekdayLabelAr(i + 1),
                                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Text('مغلق', style: GoogleFonts.tajawal(fontSize: 13)),
                            Checkbox(
                              value: _ohRows[i].closed,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() {
                                        _ohRows[i].closed = v ?? false;
                                      }),
                            ),
                          ],
                        ),
                        if (!_ohRows[i].closed) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _ohRows[i].openCtrl,
                                  textAlign: TextAlign.right,
                                  enabled: !_saving,
                                  decoration: InputDecoration(
                                    labelText: 'فتح',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _ohRows[i].closeCtrl,
                                  textAlign: TextAlign.right,
                                  enabled: !_saving,
                                  decoration: InputDecoration(
                                    labelText: 'إغلاق',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('وقت التوصيل التقريبي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: deliveryVal,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              items: kStoreDeliveryTimeOptions
                  .map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.tajawal())))
                  .toList(),
              onChanged: _saving ? null : (v) => setState(() => _deliveryChoice = v),
            ),
            const SizedBox(height: 16),
            Text('التوصيل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              title: Text('المتجر يستخدم السواقين الخاصين به', style: GoogleFonts.tajawal()),
              value: true,
              groupValue: _hasOwnDrivers,
              activeColor: AppColors.primaryOrange,
              onChanged: _saving ? null : (v) => setState(() => _hasOwnDrivers = v ?? true),
            ),
            RadioListTile<bool>(
              contentPadding: EdgeInsets.zero,
              title: Text('لا يوجد توصيل', style: GoogleFonts.tajawal()),
              value: false,
              groupValue: _hasOwnDrivers,
              activeColor: AppColors.primaryOrange,
              onChanged: _saving ? null : (v) => setState(() => _hasOwnDrivers = v ?? false),
            ),
            if (_hasOwnDrivers) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _shippingAmount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'رسوم التوصيل (دينار)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _freeShippingThreshold,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'الحد الأدنى للطلب للتوصيل المجاني (اختياري)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text('المناطق التي يوصل لها', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text('كل الأردن', style: GoogleFonts.tajawal()),
                    selected: _allJordanDelivery,
                    onSelected: _saving
                        ? null
                        : (v) => setState(() {
                              _allJordanDelivery = v;
                              if (v) _selectedAreas.clear();
                            }),
                  ),
                  ...kJordanRegions.map(
                    (r) => FilterChip(
                      label: Text(r, style: GoogleFonts.tajawal(fontSize: 12)),
                      selected: !_allJordanDelivery && _selectedAreas.contains(r),
                      onSelected: _saving
                          ? null
                          : (v) => setState(() {
                                _allJordanDelivery = false;
                                if (v) {
                                  _selectedAreas.add(r);
                                } else {
                                  _selectedAreas.remove(r);
                                }
                              }),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : () => _saveAll(d),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primaryOrange, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('حفظ جميع التغييرات', style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        );
      },
    );
  }
}
