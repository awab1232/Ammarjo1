import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/product_repository.dart';
import '../../../../core/widgets/feature_state_builder.dart';
import '../../../store/domain/wp_home_banner.dart';
import '../../../../core/firebase/user_notifications_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/jordan_phone.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/premium_categories_strip.dart';
import '../../../communication/data/unified_chat_repository.dart';
import '../../../communication/domain/unified_chat_models.dart';
import '../../../communication/presentation/unified_chat_page.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/session/backend_identity_controller.dart';
import '../../data/service_requests_repository.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/technician_notifications_repository.dart';
import '../../data/technicians_repository.dart';
import '../../domain/maintenance_models.dart';
import 'technician_detail_page.dart';
import 'technician_list_screen.dart';

/// AmmarJo Maintenance — فنيون معتمدون وحجز خدمة.
class MaintenancePage extends StatefulWidget {
  const MaintenancePage({
    super.key,
    this.onOpenDrawer,
    this.initialCategoryId,
    this.onOpenTechnicianDashboard,
  });

  final VoidCallback? onOpenDrawer;
  final String? initialCategoryId;
  final VoidCallback? onOpenTechnicianDashboard;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _filterCategoryId;
  int _techSpecRetryKey = 0;
  String _selectedSpecialtyLabel = '';

  Future<({String description, Uint8List? imageBytes})?> _askServiceDescription(BuildContext context, String techName) async {
    final ctrl = TextEditingController();
    Uint8List? imageBytes;
    final v = await showDialog<({String description, Uint8List? imageBytes})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text('شرح الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  minLines: 3,
                  maxLines: 6,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(),
                  decoration: InputDecoration(
                    hintText: 'اكتب وصف المشكلة أو المطلوب من الفني $techName',
                    hintStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800, maxHeight: 1800);
                    if (picked == null) return;
                    final bytes = await picked.readAsBytes();
                    setStateModal(() => imageBytes = bytes);
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(imageBytes == null ? 'إضافة صورة (اختياري)' : 'تغيير الصورة', style: GoogleFonts.tajawal()),
                ),
                if (imageBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(imageBytes!, height: 110, width: double.infinity, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: InkWell(
                            onTap: () => setStateModal(() => imageBytes = null),
                            child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, color: Colors.white, size: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.tajawal()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              onPressed: () => Navigator.pop(ctx, (description: ctrl.text.trim(), imageBytes: imageBytes)),
              child: Text('إرسال', style: GoogleFonts.tajawal(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (v == null || v.description.isEmpty) return null;
    return v;
  }

  @override
  void initState() {
    super.initState();
    _filterCategoryId = widget.initialCategoryId;
  }

  @override
  void didUpdateWidget(covariant MaintenancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategoryId != oldWidget.initialCategoryId) {
      _filterCategoryId = widget.initialCategoryId;
    }
  }

  Future<void> _bookTechnician(BuildContext context, TechnicianProfile tech, String categoryHint) async {
    final store = context.read<StoreController>();
    final email = store.profile?.email.trim() ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('سجّل الدخول لحجز الفني.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final techEmail = (tech.email ?? '').trim();
    if (techEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('هذا الفني تجريبي حالياً. اختر فنياً مسجلاً بحساب حقيقي.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final req = await _askServiceDescription(context, tech.displayName);
    if (req == null || req.description.isEmpty) return;
    final categoryId = _filterCategoryId ?? 'plumber';
    String requestId;
    try {
      requestId = await ServiceRequestsRepository.instance.createServiceRequestWithImage(
        technicianId: tech.id,
        title: 'طلب فني: ${tech.displayName} — $categoryHint',
        categoryId: categoryId,
        customerEmail: email,
        description: req.description,
        technicianEmail: techEmail,
        imageBytes: req.imageBytes,
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال الطلب حالياً. حاول مرة أخرى.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    String? chatId;
    try {
      final myPhone = dialablePhoneFromProfileEmail(email) ?? '';
      chatId = await UnifiedChatRepository.instance.ensureChat(
        kind: UnifiedChatKind.technicianCustomer,
        contextId: requestId,
        currentUserEmail: email,
        currentUserPhone: myPhone,
        peerEmail: techEmail,
        peerPhone: (tech.phone ?? '').trim(),
        technicianId: tech.id,
        peerDisplayName: tech.displayName,
        contextTitle: 'طلب فني #$requestId',
        contextSubtitle: categoryHint,
        contextImageUrl: tech.photoUrl,
        peerFirebaseUid: tech.id,
      );
      await ServiceRequestsRepository.instance.attachChatIdToRequest(requestId, chatId);
      await UnifiedChatRepository.instance.sendText(
        chatId: chatId,
        senderEmail: email,
        text: 'طلب خدمة جديد:\n${req.description}',
      );
      final uname = store.profile?.fullName?.trim().isNotEmpty == true
          ? store.profile!.fullName!.trim()
          : (FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty == true
              ? FirebaseAuth.instance.currentUser!.displayName!.trim()
              : email.split('@').first);
      await UserNotificationsRepository.notifyServiceRequestToTechnician(
        technicianEmail: techEmail,
        clientName: uname,
        description: req.description,
        requestId: requestId,
        chatId: chatId,
      );
    } on Object {
      debugPrint('MaintenancePage: request chat bootstrap failed.');
    }
    if (!context.mounted) return;
    if (chatId != null && chatId.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء طلبك الفني. يمكنك التواصل مع الفني هنا.', style: GoogleFonts.tajawal())),
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => UnifiedChatPage.resume(existingChatId: chatId!, threadTitle: 'طلب فني #$requestId'),
        ),
      );
      return;
    }
    final categoryName = MaintenanceServiceCategory.labelForId(categoryId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إرسال طلبك إلى $categoryName بنجاح.', style: GoogleFonts.tajawal())),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = context.watch<StoreController>();
    final technicianEmail = store.profile?.email.trim() ?? '';
    final me = BackendIdentityController.instance.me;
    final isTechnicianApproved =
        PermissionService.normalizeRole(me?.role ?? '') == PermissionService.roleTechnician;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: false,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.maintenanceHeaderGradient),
        ),
        centerTitle: true,
        leading: widget.onOpenDrawer != null
            ? IconButton(
                icon: const Icon(Icons.menu_outlined),
                onPressed: widget.onOpenDrawer,
              )
            : null,
        title: Text(
          'عمّار جو للصيانة',
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white),
        ),
        actions: [
          if (isTechnicianApproved && widget.onOpenTechnicianDashboard != null)
            FutureBuilder<FeatureState<int>>(
              future: TechnicianNotificationsRepository.instance.fetchUnreadCount(technicianEmail),
              builder: (context, snap) {
                final unread = switch (snap.data) {
                  FeatureSuccess(:final data) => data,
                  _ => 0,
                };
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'لوحة الفني',
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      onPressed: widget.onOpenTechnicianDashboard,
                    ),
                    if (unread > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$unread',
                            style: GoogleFonts.tajawal(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'لا تشيل هم الصيانة.. أفضل الفنيين بثقة واحتراف.',
                textAlign: TextAlign.right,
                maxLines: 2,
                style: GoogleFonts.tajawal(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: FutureBuilder<FeatureState<List<WpHomeBannerSlide>>>(
                future: context.read<ProductRepository>().fetchHomeBanners(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Container(
                      height: 150,
                      margin: const EdgeInsets.all(16),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const SizedBox.shrink();
                  }
                  return buildFeatureStateUi<List<WpHomeBannerSlide>>(
                    context: context,
                    state: snap.data!,
                    dataBuilder: (context, slides) {
                      return Container(
                        height: 150,
                        margin: const EdgeInsets.all(16),
                        child: slides.isEmpty
                            ? Center(
                                child: Text(
                                  'Service temporarily unavailable',
                                  style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                                ),
                              )
                            : PageView.builder(
                                itemCount: slides.length,
                                itemBuilder: (context, i) {
                                  final raw = slides[i].imageUrl;
                                  final url = webSafeImageUrl(raw);
                                  if (url.isEmpty) {
                                    return Center(
                                      child: Text(
                                        'Service temporarily unavailable',
                                        style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                                      ),
                                    );
                                  }
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: AmmarCachedImage(
                                      imageUrl: url,
                                      width: double.infinity,
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                },
                              ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'اختر نوع الخدمة',
                    style: GoogleFonts.tajawal(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.heading,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(Icons.swipe_rounded, size: 14, color: AppColors.primaryOrange.withValues(alpha: 0.9)),
                      const SizedBox(width: 6),
                      Text(
                        'اسحب لعرض كل التخصصات',
                        style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<FeatureState<List<MaintenanceServiceCategory>>>(
              key: ValueKey<int>(_techSpecRetryKey),
              future: TechniciansRepository.instance.fetchTechSpecialties(),
              builder: (context, snap) {
                if (snap.hasError) {
                  final isTimeout = snap.error is TimeoutException;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isTimeout
                              ? 'انتهت مهلة الاتصال، يرجى التحقق من اتصالك بالإنترنت'
                              : 'تعذّر تحميل التخصصات: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => setState(() => _techSpecRetryKey++),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                          child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
                  );
                }
                final categories = switch (snap.data) {
                  FeatureSuccess(:final data) => data,
                  _ => MaintenanceServiceCategory.grid,
                };
                final maps = categories
                    .map(
                      (c) => <String, dynamic>{
                        'name': c.labelAr,
                        'imageUrl': (c.backgroundImageUrl != null && c.backgroundImageUrl!.trim().isNotEmpty)
                            ? webSafeImageUrl(c.backgroundImageUrl!)
                            : null,
                      },
                    )
                    .toList();
                return PremiumCategoriesStrip(
                  categories: maps,
                  selectedName: _selectedSpecialtyLabel,
                  onSelect: (name, _) {
                    final idx = categories.indexWhere((c) => c.labelAr == name);
                    if (idx < 0) return;
                    final cat = categories[idx];
                    setState(() {
                      _selectedSpecialtyLabel = name;
                      _filterCategoryId = cat.id;
                    });
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => TechnicianListScreen(category: cat),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_filterCategoryId != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ActionChip(
                    label: Text('إظهار كل الفنيين', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                    onPressed: () => setState(() => _filterCategoryId = null),
                    backgroundColor: AppColors.accentLight,
                    side: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'فنّيون متاحون',
                    style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.heading),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<FeatureState<List<TechnicianProfile>>>(
              future: TechniciansRepository.instance.fetchTechnicians(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'تعذّر تحميل الفنيين: ${snap.error}',
                      style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                    ),
                  );
                }
                final state = snap.requireData;
                final allRaw = switch (state) {
                  FeatureSuccess(:final data) => data,
                  _ => <TechnicianProfile>[],
                };
                final all = filterTechniciansByProfileCity(allRaw, store.profile?.city ?? 'all');
                final list = _filterCategoryId == null
                    ? all
                    : all.where((t) => t.categoryId == _filterCategoryId).toList();
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: EmptyStateWidget(
                      type: EmptyStateType.technicians,
                      onAction: () => setState(() => _filterCategoryId = null),
                      actionLabel: 'إظهار كل الفنيين',
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: list.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final tech = list[i];
                    return _TechnicianCard(
                      tech: tech,
                      categoryHint: _filterCategoryId != null
                          ? (MaintenanceServiceCategory.grid.where((c) => c.id == _filterCategoryId).firstOrNull?.labelAr ?? 'خدمة')
                          : 'صيانة',
                      onBook: () => _bookTechnician(
                        context,
                        tech,
                        _filterCategoryId != null
                            ? (MaintenanceServiceCategory.grid.where((c) => c.id == _filterCategoryId).firstOrNull?.labelAr ?? 'خدمة')
                            : 'صيانة',
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (kIsWeb) const SliverToBoxAdapter(child: _MaintenanceWebInlineFooter()),
        ],
      ),
    );
  }
}

class _MaintenanceWebInlineFooter extends StatelessWidget {
  const _MaintenanceWebInlineFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      color: Colors.grey.shade100,
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        runSpacing: 16,
        spacing: 16,
        children: [
          _footerColumn(context, 'عن AmmarJo', const [('من نحن', '/about'), ('مدونتنا', '/blog')]),
          _footerColumn(
            context,
            'القوانين',
            const [('سياسة الخصوصية', '/privacy'), ('شروط الاستخدام', '/terms'), ('سياسة الاسترجاع', '/return-policy')],
          ),
        ],
      ),
    );
  }

  Widget _footerColumn(BuildContext context, String title, List<(String, String)> links) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...links.map(
          (l) => TextButton(
            onPressed: () => Navigator.of(context).pushNamed(l.$2),
            child: Text(l.$1, style: GoogleFonts.tajawal()),
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}

class _TechnicianCard extends StatelessWidget {
  const _TechnicianCard({
    required this.tech,
    required this.categoryHint,
    required this.onBook,
  });

  final TechnicianProfile tech;
  final String categoryHint;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final fullStars = tech.rating.round().clamp(0, 5);
    return Material(
      color: AppColors.background,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => TechnicianDetailPage(
                tech: tech,
                categoryHint: categoryHint,
                onBookService: onBook,
              ),
            ),
          );
        },
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.surfaceSecondary,
              child: CircleAvatar(
                radius: 31,
                backgroundColor: AppColors.background,
                child: (tech.photoUrl != null && tech.photoUrl!.isNotEmpty)
                    ? ClipOval(
                        child: Image.network(
                          tech.photoUrl!,
                          width: 62,
                          height: 62,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Icon(Icons.engineering_outlined, color: AppColors.heading, size: 30),
                        ),
                      )
                    : Icon(Icons.engineering_outlined, color: AppColors.heading, size: 30),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tech.displayName,
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.heading),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tech.specialties.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tajawal(fontSize: 12.5, color: AppColors.textSecondary, height: 1.3),
                  ),
                  if (tech.bio != null && tech.bio!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      tech.bio!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.heading.withValues(alpha: 0.85), height: 1.35),
                    ),
                  ],
                  if (tech.phone != null && tech.phone!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${tech.phone} · ${tech.city ?? tech.locationLabel}',
                        style: GoogleFonts.tajawal(fontSize: 11.5, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (i) => Padding(
                          padding: const EdgeInsets.only(left: 1),
                          child: Icon(
                            i < fullStars ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 17,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tech.rating.toStringAsFixed(1),
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.accent, fontSize: 14),
                      ),
                      const Spacer(),
                      Icon(Icons.place_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '~${tech.distanceKm.toStringAsFixed(1)} كم · ${tech.locationLabel}',
                          style: GoogleFonts.tajawal(fontSize: 11.5, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'عرض التفاصيل والتواصل',
                        style: GoogleFonts.tajawal(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accent),
                      ),
                      const Spacer(),
                      Icon(Icons.chevron_left, color: AppColors.accent, size: 22),
                    ],
                  ),
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

