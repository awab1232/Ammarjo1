import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/session/backend_identity_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../support/presentation/open_support_chat.dart';
import '../../data/service_requests_repository.dart';
import '../../domain/maintenance_models.dart';
import '../utils/service_request_status_localizer.dart';

/// لوحة الفني — الطلبات الواردة والأرباح التقريبية.
class TechnicianDashboardPage extends StatefulWidget {
  const TechnicianDashboardPage({super.key});

  @override
  State<TechnicianDashboardPage> createState() => _TechnicianDashboardPageState();
}

class _TechnicianDashboardPageState extends State<TechnicianDashboardPage> {
  static const bool _earningsNotFromBackend = false;

  List<ServiceRequest> _requests = const <ServiceRequest>[];
  double _earnings = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (UserSession.isLoggedIn && UserSession.currentUid.isNotEmpty) {
      _loading = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = UserSession.currentUid;
      if (uid.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      await _loadRequests(uid);
    });
  }

  /// Backend authorizes `technicianId` when it matches the signed-in uid or email.
  Future<void> _loadRequests(String technicianScopeId) async {
    if (technicianScopeId.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final itemsState = await ServiceRequestsRepository.instance.getServiceRequests(
        technicianId: technicianScopeId.trim(),
        limit: 30,
      );
      final earningsScope = UserSession.currentEmail.isNotEmpty
          ? UserSession.currentEmail
          : technicianScopeId;
      final earningsState = await ServiceRequestsRepository.instance.sumEarningsForTechnician(
        earningsScope,
      );
      if (!mounted) return;
      setState(() {
        _requests = switch (itemsState) {
          FeatureSuccess(:final data) => data,
          _ => <ServiceRequest>[],
        };
        _earnings = switch (earningsState) {
          FeatureSuccess(:final data) => data,
          _ => 0,
        };
      });
    } on Object {
      debugPrint('TechnicianDashboardPage: load failed.');
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل الطلبات. تحقق من الاتصال وحاول مرة أخرى.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = BackendIdentityController.instance.me;
    final isTechnician =
        PermissionService.normalizeRole(me?.role ?? '') == PermissionService.roleTechnician;
    if (!isTechnician) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          leading: const AppBarBackButton(),
          title: Text('لوحة الفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_outlined, size: 64, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                Text(
                  'الوصول مقيّد',
                  style: GoogleFonts.tajawal(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'طلبك قيد المراجعة.\nسيتم تفعيل لوحة الفني بعد موافقة الإدارة.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final uid = UserSession.currentUid;
    final incoming = _requests.where((r) => r.status == 'pending').toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        leading: const AppBarBackButton(),
        title: Text('لوحة الفني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'احصل على مساعدة',
            icon: const Icon(Icons.support_agent, color: Colors.white),
            onPressed: () => openSupportChat(context),
          ),
          if (uid.isNotEmpty)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  tooltip: 'الإشعارات',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('الإشعارات قريباً', style: GoogleFonts.tajawal())),
                    );
                  },
                  icon: const Icon(Icons.notifications_active_rounded),
                ),
                if (incoming.isNotEmpty)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                      child: Text('${incoming.length}', style: GoogleFonts.tajawal(color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: uid.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'سجّل الدخول لعرض طلباتك.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                ),
              ),
            )
          : RefreshIndicator(
              color: AppColors.primaryOrange,
              onRefresh: () => _loadRequests(uid),
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.all(16),
                      children: const [
                        HomeStoreListSkeleton(rows: 5),
                      ],
                    )
                  : _error != null
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 80),
                            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                            const SizedBox(height: 16),
                            Center(
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: FilledButton(
                                onPressed: () => _loadRequests(uid),
                                child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        )
                      : CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: incoming.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.red.shade200),
                                        ),
                                        child: Text(
                                          'لديك ${incoming.length} طلب/رسالة جديدة من العملاء.',
                                          style: GoogleFonts.tajawal(
                                            color: Colors.red.shade900,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: _EarningsCard(jod: _earnings, isPlaceholder: _earningsNotFromBackend),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'طلبات مرتبطة بحسابك',
                                  style: GoogleFonts.tajawal(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                                child: Text(
                                  'Incoming Requests',
                                  style: GoogleFonts.tajawal(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: incoming.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                      child: Text(
                                        'لا توجد رسائل جديدة.',
                                        textAlign: TextAlign.right,
                                        style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                      itemCount: incoming.take(5).length,
                                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                                      itemBuilder: (context, i) {
                                        final n = incoming[i];
                                        return Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: AppColors.orangeLight,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: AppColors.orange.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                n.title,
                                                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, color: AppColors.navy),
                                                textAlign: TextAlign.right,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                n.description?.trim().isNotEmpty == true ? n.description!.trim() : 'طلب خدمة جديد',
                                                style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                                                textAlign: TextAlign.right,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            if (_requests.isEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                    'لا توجد طلبات بعد. عند قبولك كفني سيظهر العملاء هنا.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.4),
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.all(16),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, i) {
                                      final r = _requests[i];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: _RequestTile(
                                          request: r,
                                          onAction: (status) async {
                                            try {
                                              if (status == 'cancel') {
                                                await ServiceRequestsRepository.instance.cancelServiceRequest(r.id);
                                              } else {
                                                await ServiceRequestsRepository.instance.updateServiceRequest(
                                                  requestId: r.id,
                                                  status: status,
                                                );
                                              }
                                              if (!mounted) return;
                                              await _loadRequests(uid);
                                            } on Object {
                                              debugPrint('TechnicianDashboardPage: update request status failed.');
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(this.context).showSnackBar(
                                                SnackBar(content: Text('تعذر تحديث حالة الطلب.', style: GoogleFonts.tajawal())),
                                              );
                                            }
                                          },
                                        ),
                                      );
                                    },
                                    childCount: _requests.length,
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.jod, required this.isPlaceholder});

  final double jod;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(18),
      color: AppColors.navy,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.payments_rounded, color: AppColors.orange, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أرباح مُكمَّلة (تقريبية)',
                    style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPlaceholder ? '—' : '${jod.toStringAsFixed(2)} د.أ',
                    style: GoogleFonts.tajawal(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  if (isPlaceholder) ...[
                    const SizedBox(height: 8),
                    Text(
                      'تُحسب الأرباح من الخادم عند توفر واجهة لها.',
                      style: GoogleFonts.tajawal(color: Colors.white54, fontSize: 12, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onAction});

  final ServiceRequest request;
  final Future<void> Function(String status) onAction;

  void _openImageViewer(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          minScale: 0.7,
          maxScale: 4,
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: AmmarCachedImage(imageUrl: imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (request.imageUrl != null && request.imageUrl!.trim().isNotEmpty)
              InkWell(
                onTap: () => _openImageViewer(context, request.imageUrl!.trim()),
                borderRadius: BorderRadius.circular(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: AmmarCachedImage(imageUrl: request.imageUrl, fit: BoxFit.cover),
                  ),
                ),
              ),
            if (request.imageUrl != null && request.imageUrl!.trim().isNotEmpty) const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(request.title, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  Text(
                    '${getServiceRequestStatusArabic(request.status)} · ${request.createdAt.toString().substring(0, 16)}',
                    style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            if (request.imageUrl != null && request.imageUrl!.trim().isNotEmpty)
              Tooltip(
                message: 'عرض الصورة',
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openImageViewer(context, request.imageUrl!.trim()),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.image_outlined, color: AppColors.accent, size: 20),
                  ),
                ),
              ),
            Chip(
              label: Text(request.categoryId, style: GoogleFonts.tajawal(fontSize: 11)),
              backgroundColor: AppColors.orangeLight,
            ),
            const SizedBox(width: 6),
            if (request.status == 'assigned' || request.status == 'pending') ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade900,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('رفض الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                      content: Text(
                        'هل أنت متأكد من رفض هذا الطلب؟ سيتم محاولة تعيين فني آخر.',
                        style: GoogleFonts.tajawal(),
                        textAlign: TextAlign.right,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('إلغاء', style: GoogleFonts.tajawal()),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                          child: Text('رفض الطلب', style: GoogleFonts.tajawal(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await onAction('rejected');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم رفض الطلب بنجاح', style: GoogleFonts.tajawal())),
                      );
                    }
                  }
                },
                child: Text('رفض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => onAction('start'),
                child: Text('بدء', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
            ] else if (request.status == 'in_progress')
              TextButton(
                onPressed: () => onAction('complete'),
                child: Text('إنهاء', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}

