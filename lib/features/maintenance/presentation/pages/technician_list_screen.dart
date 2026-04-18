import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/firebase/user_notifications_repository.dart';
import '../../../../core/utils/jordan_phone.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../../communication/data/unified_chat_repository.dart';
import '../../../communication/domain/unified_chat_models.dart';
import '../../../communication/presentation/unified_chat_page.dart';
import '../../data/service_requests_repository.dart';
import '../../../store/presentation/pages/customer_delivery_settings_page.dart';
import '../../../store/presentation/store_controller.dart';
import '../../data/technicians_repository.dart';
import '../../domain/maintenance_models.dart';

class _TechRequestDraft {
  const _TechRequestDraft({required this.description, this.imageBytes});
  final String description;
  final Uint8List? imageBytes;
}

class TechnicianListScreen extends StatelessWidget {
  const TechnicianListScreen({super.key, required this.category});

  final MaintenanceServiceCategory category;

  Future<_TechRequestDraft?> _askDescription(BuildContext context, String techName) async {
    final ctrl = TextEditingController();
    Uint8List? imageBytes;
    final result = await showDialog<_TechRequestDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: Text('شرح ما يحتاجه من الفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
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
                    hintText: 'اكتب تفاصيل الطلب للفني $techName',
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.tajawal())),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              onPressed: () => Navigator.pop(ctx, _TechRequestDraft(description: ctrl.text.trim(), imageBytes: imageBytes)),
              child: Text('إرسال', style: GoogleFonts.tajawal(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result == null || result.description.isEmpty) return null;
    return result;
  }

  Future<void> _submitRequest(BuildContext context, TechnicianProfile tech) async {
    final store = context.read<StoreController>();
    final email = store.profile?.email.trim() ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('سجّل الدخول أولاً.', style: GoogleFonts.tajawal())));
      return;
    }
    final techEmail = (tech.email ?? '').trim();
    if (techEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('هذا الفني غير موصول بحساب حالياً.', style: GoogleFonts.tajawal())),
      );
      return;
    }
    final req = await _askDescription(context, tech.displayName);
    if (req == null || req.description.isEmpty) return;
    final requestId = await ServiceRequestsRepository.instance.createServiceRequestWithImage(
      technicianId: tech.id,
      title: 'طلب فني: ${tech.displayName}',
      categoryId: category.id,
      customerEmail: email,
      description: req.description,
      technicianEmail: techEmail,
      imageBytes: req.imageBytes,
    );
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
        contextSubtitle: category.labelAr,
        contextImageUrl: tech.photoUrl,
        peerFirebaseUid: tech.id,
      );
      await ServiceRequestsRepository.instance.attachChatIdToRequest(requestId, chatId);
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
      debugPrint('TechnicianListScreen: chat bootstrap failed.');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم إرسال الطلب بنجاح، وسيتم التواصل معك قريباً.', style: GoogleFonts.tajawal())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _TechnicianListBody(category: category, askDescription: _askDescription, submitRequest: _submitRequest);
  }
}

class _TechnicianListBody extends StatefulWidget {
  const _TechnicianListBody({
    required this.category,
    required this.askDescription,
    required this.submitRequest,
  });

  final MaintenanceServiceCategory category;
  final Future<_TechRequestDraft?> Function(BuildContext, String) askDescription;
  final Future<void> Function(BuildContext, TechnicianProfile) submitRequest;

  @override
  State<_TechnicianListBody> createState() => _TechnicianListBodyState();
}

class _TechnicianListBodyState extends State<_TechnicianListBody> {
  static const int _pageSize = 20;
  final List<TechnicianProfile> _techs = <TechnicianProfile>[];
  Object? _lastDoc;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  Future<void> _loadInitial() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _techs.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    try {
      final storeCtrl = context.read<StoreController>();
      final profileCity = storeCtrl.profile?.city?.trim();
      final cityForRepo = (profileCity == null || profileCity.isEmpty) ? 'all' : profileCity;
      final page = await TechniciansRepository.instance.fetchApprovedTechniciansPage(
        specialty: widget.category.id,
        city: cityForRepo,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _techs.addAll(page.technicians);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
      });
    } on Object {
      debugPrint('TechnicianListScreen: technicians load failed.');
      if (mounted) setState(() => _loadError = 'تعذر تحميل البيانات');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final storeCtrl = context.read<StoreController>();
      final profileCity = storeCtrl.profile?.city?.trim();
      final cityForRepo = (profileCity == null || profileCity.isEmpty) ? 'all' : profileCity;
      final page = await TechniciansRepository.instance.fetchApprovedTechniciansPage(
        specialty: widget.category.id,
        city: cityForRepo,
        limit: _pageSize,
        startAfter: _lastDoc,
      );
      if (!mounted) return;
      setState(() {
        _techs.addAll(page.technicians);
        _lastDoc = page.lastDoc;
        _hasMore = page.hasMore;
      });
    } on Object {
      debugPrint('TechnicianListScreen: technicians load more failed.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _showTechnicianDetailsSheet(TechnicianProfile tech) async {
    await AppBottomSheet.show<void>(
      context: context,
      title: 'تفاصيل الفني',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tech.displayName, textAlign: TextAlign.center, style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(tech.specialties.join(' • '), textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text('التقييم: ${tech.rating.toStringAsFixed(1)}', textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text('الخبرة: ${tech.bio?.trim().isNotEmpty == true ? tech.bio!.trim() : 'فني معتمد'}',
              textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.submitRequest(context, tech);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
            child: Text('طلب الفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeCtrl = context.watch<StoreController>();
    final profileCity = storeCtrl.profile?.city?.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        leading: const AppBarBackButton(),
        title: Text(widget.category.labelAr, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: Builder(
        builder: (context) {
          if (_loadError != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(_loadError!, style: GoogleFonts.tajawal()),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _loadInitial, child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }
          if (_loading && _techs.isEmpty) {
            return const _TechniciansListShimmer();
          }
          final techs = filterTechniciansByProfileCity(_techs, profileCity ?? 'all');
          if (techs.isEmpty) {
            final filteredOut = _techs.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: EmptyStateWidget(
                type: EmptyStateType.technicians,
                customSubtitle: filteredOut ? 'لا يوجد فنيون ضمن منطقتك في هذا التخصص.' : null,
                onAction: filteredOut
                    ? () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: (_) => const CustomerDeliverySettingsPage()),
                        );
                      }
                    : _loadInitial,
                actionLabel: filteredOut ? 'تغيير المنطقة' : 'إعادة المحاولة',
              ),
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis == Axis.vertical &&
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 320) {
                _loadMore();
              }
              return false;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: techs.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index >= techs.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: HomeStoreListSkeleton(rows: 2),
                  );
                }
                final tech = techs[index];
              final stars = tech.rating.round().clamp(1, 5);
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                elevation: 2,
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  onTap: () {
                    _showTechnicianDetailsSheet(tech);
                  },
                  leading: CircleAvatar(
                    backgroundColor: AppColors.orangeLight,
                    child: Icon(Icons.engineering_rounded, color: AppColors.navy),
                  ),
                  title: Text(tech.displayName, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    [
                      tech.specialties.join(' · '),
                      if (tech.bio != null && tech.bio!.trim().isNotEmpty) tech.bio!,
                      if (tech.phone != null && tech.phone!.trim().isNotEmpty)
                        '${tech.phone} · ${tech.city ?? ''}',
                      '${List.filled(stars, '★').join()} ${tech.rating.toStringAsFixed(1)} · ~${tech.distanceKm.toStringAsFixed(1)} كم',
                    ].where((s) => s.isNotEmpty).join('\n'),
                    style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                  ),
                  isThreeLine: true,
                  trailing: FilledButton(
                    onPressed: () => widget.submitRequest(context, tech),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('اطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  ),
                ),
              );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TechniciansListShimmer extends StatelessWidget {
  const _TechniciansListShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

