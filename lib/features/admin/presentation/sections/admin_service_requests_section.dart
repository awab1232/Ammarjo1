import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/firebase/user_notifications_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../maintenance/data/service_requests_repository.dart';
import '../../../maintenance/domain/maintenance_models.dart';
import '../../../maintenance/presentation/utils/service_request_status_localizer.dart';
import '../../data/backend_admin_client.dart';

class AdminServiceRequestsSection extends StatefulWidget {
  const AdminServiceRequestsSection({super.key});

  @override
  State<AdminServiceRequestsSection> createState() => _AdminServiceRequestsSectionState();
}

class _AdminServiceRequestsSectionState extends State<AdminServiceRequestsSection> {
  static const int _pageSize = 20;
  String _statusFilter = 'all';
  String _technicianFilter = 'all';
  final List<ServiceRequest> _requests = <ServiceRequest>[];
  String? _nextCursor;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
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
      _requests.clear();
      _nextCursor = null;
      _hasMore = true;
    });
    try {
      final resultState = await ServiceRequestsRepository.instance.getServiceRequestsPage(
        limit: _pageSize,
        cursor: null,
        statusFilter: _statusFilter == 'all' ? null : _statusFilter,
        technicianId: _technicianFilter == 'all' ? null : _technicianFilter,
      );
      final result = switch (resultState) {
        FeatureSuccess(:final data) => data,
        FeatureFailure(:final message) => throw StateError(message),
        _ => throw StateError('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
      };
      if (!mounted) return;
      setState(() {
        _requests.addAll(result.items);
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
      });
    } on Object {
      debugPrint('❌ Error loading service requests');
      if (!mounted) return;
      setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    final cur = _nextCursor;
    if (cur == null || cur.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final resultState = await ServiceRequestsRepository.instance.getServiceRequestsPage(
        limit: _pageSize,
        cursor: cur,
        statusFilter: _statusFilter == 'all' ? null : _statusFilter,
        technicianId: _technicianFilter == 'all' ? null : _technicianFilter,
      );
      final result = switch (resultState) {
        FeatureSuccess(:final data) => data,
        FeatureFailure(:final message) => throw StateError(message),
        _ => throw StateError('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
      };
      if (!mounted) return;
      setState(() {
        _requests.addAll(result.items);
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
      });
    } on Object {
      debugPrint('❌ Error loading more');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  String _dateLine(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!Firebase.apps.isNotEmpty) {
      return Center(child: Text('Firebase غير جاهز', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: _TechnicianFilterDropdown(
                  value: _technicianFilter,
                  onChanged: (v) {
                    setState(() => _technicianFilter = v);
                    _loadInitial();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _statusFilter,
                  decoration: InputDecoration(
                    labelText: 'الحالة',
                    labelStyle: GoogleFonts.tajawal(),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(value: 'pending', child: Text(getServiceRequestStatusArabic('pending'))),
                    DropdownMenuItem(value: 'in_progress', child: Text(getServiceRequestStatusArabic('in_progress'))),
                    DropdownMenuItem(value: 'completed', child: Text(getServiceRequestStatusArabic('completed'))),
                    DropdownMenuItem(value: 'cancelled', child: Text(getServiceRequestStatusArabic('cancelled'))),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _statusFilter = v);
                    _loadInitial();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (_hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('حدث خطأ في تحميل طلبات الخدمة'),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: _loadInitial, child: const Text('إعادة المحاولة')),
                    ],
                  ),
                );
              }
              if (_isLoading && _requests.isEmpty) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primaryOrange));
              }
              if (_requests.isEmpty) {
                return Center(child: Text('لا توجد طلبات خدمة', style: GoogleFonts.tajawal(color: AppColors.textSecondary)));
              }
              return RefreshIndicator(
                onRefresh: _loadInitial,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (scrollInfo) {
                    if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                      if (_hasMore && !_isLoadingMore) {
                        _loadMore();
                      }
                    }
                    return false;
                  },
                  child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _requests.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  if (i == _requests.length) {
                    return _isLoadingMore
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(child: CircularProgressIndicator(color: AppColors.primaryOrange)),
                          )
                        : const SizedBox.shrink();
                  }
                  final req = _requests[i];
                  final img =
                      req.imageUrl?.toString().trim() ?? (throw StateError('unexpected_empty_response'));
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openRequestDialog(context, req),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (img.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 72,
                                height: 72,
                                child: AmmarCachedImage(imageUrl: img, fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('رقم الطلب: ${req.id}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 6),
                                Text(
                                  'العميل: ${req.customerName ?? req.customerEmail ?? '-'}',
                                  style: GoogleFonts.tajawal(fontSize: 13),
                                  textAlign: TextAlign.right,
                                ),
                                Text(
                                  'الفني: ${req.assignedTechnicianEmail ?? '-'}',
                                  style: GoogleFonts.tajawal(fontSize: 13),
                                  textAlign: TextAlign.right,
                                ),
                                Row(
                                  children: [
                                    Chip(label: Text(getServiceRequestStatusArabic(req.status), style: GoogleFonts.tajawal(fontSize: 11))),
                                    const Spacer(),
                                    Text(
                                      _dateLine(req.createdAt),
                                      style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                                if ((req.description?.toString().trim().isNotEmpty ??
                                    (throw StateError('unexpected_empty_response'))))
                                  Text(
                                    req.description.toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openRequestDialog(BuildContext context, ServiceRequest req) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ServiceRequestEditorDialog(request: req),
    );
  }
}

class _TechnicianFilterDropdown extends StatelessWidget {
  const _TechnicianFilterDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: BackendAdminClient.instance.fetchTechnicians(),
      builder: (context, snap) {
        final raw = snap.data?['items'];
        final docs = <Map<String, dynamic>>[];
        if (raw is List) {
          for (final e in raw) {
            if (e is Map &&
                (e['status']?.toString() ?? (throw StateError('unexpected_empty_response'))) == 'approved') {
              docs.add(Map<String, dynamic>.from(e));
            }
          }
        }
        final items = <DropdownMenuItem<String>>[
          const DropdownMenuItem(value: 'all', child: Text('كل الفنيين')),
          ...docs.map((d) {
            final id = d['id']?.toString() ?? (throw StateError('unexpected_empty_response'));
            final name = d['display_name']?.toString().trim() ?? d['displayName']?.toString().trim();
            return DropdownMenuItem<String>(
              value: id,
              child: Text((name != null && name.isNotEmpty) ? name : id),
            );
          }),
        ];
        final effective = items.any((e) => e.value == value) ? value : 'all';
        return DropdownButtonFormField<String>(
          initialValue: effective,
          decoration: InputDecoration(
            labelText: 'الفني',
            labelStyle: GoogleFonts.tajawal(),
            border: const OutlineInputBorder(),
          ),
          items: items,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        );
      },
    );
  }
}

class _ServiceRequestEditorDialog extends StatefulWidget {
  const _ServiceRequestEditorDialog({required this.request});

  final ServiceRequest request;

  @override
  State<_ServiceRequestEditorDialog> createState() => _ServiceRequestEditorDialogState();
}

class _ServiceRequestEditorDialogState extends State<_ServiceRequestEditorDialog> {
  String? _status;
  String? _technicianId;
  bool _saving = false;
  late final TextEditingController _adminNoteCtrl;

  @override
  void initState() {
    super.initState();
    _status = widget.request.status;
    _technicianId = widget.request.assignedTechnicianId;
    _adminNoteCtrl =
        TextEditingController(text: widget.request.adminNote ?? (throw StateError('unexpected_empty_response')));
  }

  @override
  void dispose() {
    _adminNoteCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _customerData() async {
    final cid = widget.request.customerId?.trim() ?? (throw StateError('unexpected_empty_response'));
    if (cid.isEmpty) throw StateError('unexpected_empty_response');
    try {
      final u = await BackendAdminClient.instance.getUserById(cid);
      if (u == null) throw StateError('unexpected_empty_response');
      return <String, dynamic>{
        'fullName': u['email']?.toString() ?? (throw StateError('unexpected_empty_response')),
        'email': u['email']?.toString() ?? (throw StateError('unexpected_empty_response')),
        'phoneLocal': u['phone']?.toString(),
      };
    } on Object {
      debugPrint('[AdminServiceRequestsSection] _customerData failed');
      throw StateError('unexpected_empty_response');
    }
  }

  Future<FeatureState<List<TechnicianProfile>>> _approvedTechs() async {
    final raw = await BackendAdminClient.instance.fetchTechnicians();
    final items = raw?['items'];
    if (items is! List) return FeatureState.failure('Invalid technicians payload.');
    final out = <TechnicianProfile>[];
    for (final e in items) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      if ((m['status']?.toString() ?? (throw StateError('unexpected_empty_response'))) != 'approved') continue;
      final id = m['id']?.toString() ?? (throw StateError('unexpected_empty_response'));
      if (id.isEmpty) continue;
      final specs = m['specialties'];
      out.add(
        TechnicianProfile(
          id: id,
          displayName: m['display_name']?.toString() ?? m['displayName']?.toString() ?? 'فني',
          specialties: specs is List ? specs.map((x) => x.toString()).toList() : const <String>[],
          rating: 4.5,
          distanceKm: 1,
          locationLabel: m['city']?.toString() ?? 'عمان',
          email: m['email']?.toString(),
          categoryId: m['category']?.toString(),
          phone: m['phone']?.toString(),
          city: m['city']?.toString(),
          status: m['status']?.toString(),
        ),
      );
    }
    return FeatureState.success(out);
  }

  Future<void> _save(List<TechnicianProfile> techs) async {
    setState(() => _saving = true);
    final selected = techs.where((t) => t.id == _technicianId).toList();
    final sel = selected.isNotEmpty ? selected.first : null;
    final newTechEmail = sel?.email?.trim().toLowerCase();
    final changedStatus = _status != widget.request.status;
    final changedTech = _technicianId != widget.request.assignedTechnicianId || newTechEmail != widget.request.assignedTechnicianEmail?.trim().toLowerCase();
    try {
      await ServiceRequestsRepository.instance.updateServiceRequest(
        requestId: widget.request.id,
        assignedTechnicianId: _technicianId,
        assignedTechnicianEmail: newTechEmail,
        status: _status,
        adminNote: _adminNoteCtrl.text,
      );

      final customerId =
          widget.request.customerId?.trim() ?? (throw StateError('unexpected_empty_response'));
      if (customerId.isNotEmpty) {
        try {
          await UserNotificationsRepository.sendNotificationToUser(
            userId: customerId,
            title: 'تحديث حالة طلبك الفني',
            body: 'تم تغيير حالة طلبك #${widget.request.id} إلى ${getServiceRequestStatusArabic(_status ?? widget.request.status)}',
            type: 'service_request_update',
            referenceId: widget.request.id,
          );
        } on Object {
          debugPrint('[AdminServiceRequestsSection] notify customer failed');
        }
      }

      final techEmail = sel?.email?.trim();
      if (techEmail != null && techEmail.isNotEmpty && (changedTech || changedStatus)) {
        try {
          await UserNotificationsRepository.sendNotificationToUserByEmail(
            email: techEmail,
            title: changedTech ? 'طلب فني جديد' : 'تحديث طلب فني',
            body: changedTech
                ? 'تم تعيين طلب #${widget.request.id} لك'
                : 'تم تغيير حالة طلب #${widget.request.id} إلى ${getServiceRequestStatusArabic(_status ?? widget.request.status)}',
            type: 'service_request_update',
            referenceId: widget.request.id,
          );
        } on Object {
          debugPrint('[AdminServiceRequestsSection] notify technician by email failed');
        }
      }

      if (mounted) Navigator.pop(context);
    } on Object {
      debugPrint('[AdminServiceRequestsSection] updateServiceRequest failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openImageViewer(String imageUrl) {
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
    return AlertDialog(
      title: Text('طلب خدمة #${widget.request.id}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      content: FutureBuilder<List<dynamic>>(
        future: Future.wait<dynamic>([_customerData(), _approvedTechs()]),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()));
          }
          final customer = (snap.data![0] as Map<String, dynamic>?);
          final techsState = snap.data![1] as FeatureState<List<TechnicianProfile>>;
          final techs = switch (techsState) {
            FeatureSuccess(:final data) => data,
            _ => <TechnicianProfile>[],
          };
          final currentTechValue = techs.any((t) => t.id == _technicianId) ? _technicianId : null;
          return SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'العميل: ${(customer?['fullName'] ?? widget.request.customerName ?? '-').toString()}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'البريد: ${(customer?['email'] ?? widget.request.customerEmail ?? '-').toString()}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontSize: 13),
                  ),
                  Text(
                    'الهاتف: ${(customer?['phoneLocal'] ?? widget.request.customerPhone ?? '-').toString()}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontSize: 13),
                  ),
                  Text(
                    'التصنيف: ${widget.request.categoryName ?? widget.request.categoryId}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontSize: 13),
                  ),
                  Text(
                    'الفني المعيّن حالياً: ${widget.request.assignedTechnicianEmail ?? '-'}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Text('وصف المشكلة', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    widget.request.description ?? widget.request.notes ?? '-',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  if (widget.request.imageUrl != null && widget.request.imageUrl!.trim().isNotEmpty) ...[
                    Text('الصورة المرفقة', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _openImageViewer(widget.request.imageUrl!.trim()),
                      borderRadius: BorderRadius.circular(12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 170,
                          child: AmmarCachedImage(imageUrl: widget.request.imageUrl, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ] else
                    Text(
                      'لا توجد صورة مرفقة',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: currentTechValue,
                    decoration: InputDecoration(
                      labelText: 'الفني المعين',
                      labelStyle: GoogleFonts.tajawal(),
                      border: const OutlineInputBorder(),
                    ),
                    items: techs
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t.id,
                            child: Text('${t.displayName} (${t.email ?? t.id})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _technicianId = v;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: InputDecoration(
                      labelText: 'الحالة',
                      labelStyle: GoogleFonts.tajawal(),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'pending', child: Text(getServiceRequestStatusArabic('pending'))),
                      DropdownMenuItem(value: 'in_progress', child: Text(getServiceRequestStatusArabic('in_progress'))),
                      DropdownMenuItem(value: 'completed', child: Text(getServiceRequestStatusArabic('completed'))),
                      DropdownMenuItem(value: 'cancelled', child: Text(getServiceRequestStatusArabic('cancelled'))),
                    ],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _adminNoteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات الأدمن',
                      labelStyle: GoogleFonts.tajawal(),
                      border: const OutlineInputBorder(),
                    ),
                    style: GoogleFonts.tajawal(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('إلغاء', style: GoogleFonts.tajawal()),
        ),
        FutureBuilder<FeatureState<List<TechnicianProfile>>>(
          future: _approvedTechs(),
          builder: (context, snap) {
            final techs = switch (snap.data) {
              FeatureSuccess(:final data) => data,
              _ => <TechnicianProfile>[],
            };
            return FilledButton(
              onPressed: _saving ? null : () => _save(techs),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('حفظ التغييرات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            );
          },
        ),
      ],
    );
  }
}
