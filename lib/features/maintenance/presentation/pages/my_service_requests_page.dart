import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../data/service_requests_repository.dart';
import '../../domain/maintenance_models.dart';
import '../utils/service_request_status_localizer.dart';
import '../../../../core/services/backend_orders_client.dart';

class MyServiceRequestsPage extends StatefulWidget {
  const MyServiceRequestsPage({super.key});

  @override
  State<MyServiceRequestsPage> createState() => _MyServiceRequestsPageState();
}

class _MyServiceRequestsPageState extends State<MyServiceRequestsPage> {
  static const int _pageSize = 20;
  final List<ServiceRequest> _requests = <ServiceRequest>[];
  String? _nextCursor;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _techLoading = false;
  final Map<String, Map<String, dynamic>> _techById = <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  String _date(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

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

  Future<void> _loadInitial() async {
    if (_isLoading) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
      _requests.clear();
      _nextCursor = null;
      _hasMore = true;
    });
    try {
      final resultState = await ServiceRequestsRepository.instance.getMyServiceRequestsPage(
        customerId: uid,
        limit: _pageSize,
        cursor: null,
      );
      final result = switch (resultState) {
        FeatureSuccess(:final data) => data,
        FeatureFailure(:final message) => throw StateError(message),
        _ => throw StateError('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
      };
      await _loadTechnicians();
      if (!mounted) return;
      setState(() {
        _requests.addAll(result.items);
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
      });
    } on Object {
      debugPrint('MyServiceRequestsPage: load requests failed.');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Ø­Ø¯Ø« Ø®Ø·Ø£ ÙÙŠ ØªØ­Ù…ÙŠÙ„ Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ø®Ø¯Ù…Ø©';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTechnicians() async {
    if (_techLoading) return;
    _techLoading = true;
    try {
      final items = await BackendOrdersClient.instance.fetchAdminTechnicians(limit: 200, offset: 0);
      _techById
        ..clear()
        ..addEntries(
          items.map((d) => MapEntry((d['id'] ?? d['uid'] ?? '').toString(), d)).where((e) => e.key.isNotEmpty),
        );
    } on Object {
      debugPrint('[MyServiceRequestsPage] load technicians failed.');
    } finally {
      _techLoading = false;
    }
  }

  Future<void> _loadMore(String uid) async {
    if (_loadingMore || !_hasMore) return;
    final cur = _nextCursor;
    if (cur == null || cur.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final resultState = await ServiceRequestsRepository.instance.getMyServiceRequestsPage(
        customerId: uid,
        limit: _pageSize,
        cursor: cur,
      );
      final result = switch (resultState) {
        FeatureSuccess(:final data) => data,
        FeatureFailure(:final message) => throw StateError(message),
        _ => throw StateError('FAILED_TO_LOAD_SERVICE_REQUESTS_PAGE'),
      };
      if (!mounted) return;
      setState(() {
        final existing = _requests.map((e) => e.id).toSet();
        _requests.addAll(result.items.where((e) => !existing.contains(e.id)));
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
      });
    } on Object {
      debugPrint('MyServiceRequestsPage: load more failed.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ø²ÙŠØ¯ Ø­Ø§Ù„ÙŠØ§Ù‹.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _showDetails(
    BuildContext context,
    ServiceRequest req,
    Map<String, Map<String, dynamic>> techById,
  ) async {
    final tData = req.assignedTechnicianId != null ? techById[req.assignedTechnicianId!] : null;
    final tName = tData?['displayName']?.toString().trim();
    final tEmail = tData?['email']?.toString().trim();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('ØªÙØ§ØµÙŠÙ„ Ø§Ù„Ø·Ù„Ø¨ #${req.id}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ø§Ù„ÙˆØµÙ', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700), textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text((req.description ?? req.notes ?? '-'), textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
                const SizedBox(height: 10),
                if (req.imageUrl != null && req.imageUrl!.trim().isNotEmpty) ...[
                  Text('Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ù…Ø±ÙÙ‚Ø©', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700), textAlign: TextAlign.right),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _openImageViewer(context, req.imageUrl!.trim()),
                    borderRadius: BorderRadius.circular(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 170,
                        child: AmmarCachedImage(imageUrl: req.imageUrl, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text('Ø§Ù„ØªØµÙ†ÙŠÙ: ${req.categoryName ?? req.categoryId}', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
                Text('Ø§Ù„Ø­Ø§Ù„Ø©: ${getServiceRequestStatusArabic(req.status)}', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
                Text(
                  'Ø§Ù„ÙÙ†ÙŠ: ${tName != null && tName.isNotEmpty ? tName : 'Ù„Ù… ÙŠØªÙ… ØªØ¹ÙŠÙŠÙ† ÙÙ†ÙŠ Ø¨Ø¹Ø¯'}',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(),
                ),
                if (tEmail != null && tEmail.isNotEmpty)
                  Text('Ø¨Ø±ÙŠØ¯ Ø§Ù„ÙÙ†ÙŠ: $tEmail', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 13)),
                const SizedBox(height: 10),
                Text('ØªØ§Ø±ÙŠØ® Ø§Ù„Ø¥Ù†Ø´Ø§Ø¡: ${_date(req.createdAt)}', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontSize: 13)),
                Text(
                  'Ø¢Ø®Ø± ØªØ­Ø¯ÙŠØ«: ${req.updatedAt != null ? _date(req.updatedAt!) : '-'}',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.tajawal(fontSize: 13),
                ),
                const SizedBox(height: 10),
                Text('Ù…Ù„Ø§Ø­Ø¸Ø§Øª Ø§Ù„Ø£Ø¯Ù…Ù†', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700), textAlign: TextAlign.right),
                const SizedBox(height: 4),
                Text((req.adminNote?.trim().isNotEmpty ?? false) ? req.adminNote! : 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…Ù„Ø§Ø­Ø¸Ø§Øª', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Ø¥ØºÙ„Ø§Ù‚', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: const AppBarBackButton(),
        title: Text('Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ø®Ø¯Ù…Ø©', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: uid == null
          ? Center(child: Text('Ø³Ø¬Ù‘Ù„ Ø§Ù„Ø¯Ø®ÙˆÙ„ Ù„Ø¹Ø±Ø¶ Ø·Ù„Ø¨Ø§ØªÙƒ.', style: GoogleFonts.tajawal(color: AppColors.textSecondary)))
          : Builder(
              builder: (context) {
                if (_hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(_errorMessage ?? 'Ø­Ø¯Ø« Ø®Ø·Ø£ ÙÙŠ ØªØ­Ù…ÙŠÙ„ Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ø®Ø¯Ù…Ø©', style: GoogleFonts.tajawal()),
                        const SizedBox(height: 8),
                        ElevatedButton(onPressed: _loadInitial, child: const Text('Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ù…Ø­Ø§ÙˆÙ„Ø©')),
                      ],
                    ),
                  );
                }
                if (_isLoading && _requests.isEmpty) {
                  return const _MyRequestsShimmer();
                }
                if (_requests.isEmpty) {
                  return EmptyStateWidget(
                    type: EmptyStateType.serviceRequests,
                    onAction: _loadInitial,
                    actionLabel: 'إعادة المحاولة',
                  );
                }
                return RefreshIndicator(
                  color: AppColors.primaryOrange,
                  onRefresh: _loadInitial,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.axis == Axis.vertical && n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                        _loadMore(uid);
                      }
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _requests.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i == _requests.length) {
                          if (!_hasMore) return const SizedBox(height: 8);
                          return Center(
                            child: TextButton.icon(
                              onPressed: _loadingMore ? null : () => _loadMore(uid),
                              icon: _loadingMore
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.expand_more_rounded),
                              label: Text(_loadingMore ? 'Ø¬Ø§Ø±ÙŠ Ø§Ù„ØªØ­Ù…ÙŠÙ„...' : 'ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ø²ÙŠØ¯', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                            ),
                          );
                        }
                        final req = _requests[i];
                        final t = req.assignedTechnicianId != null ? _techById[req.assignedTechnicianId!] : null;
                        final tName = t?['displayName']?.toString().trim();
                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Ø±Ù‚Ù… Ø§Ù„Ø·Ù„Ø¨: ${req.id.substring(0, req.id.length > 8 ? 8 : req.id.length)}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Chip(
                                      label: Text(getServiceRequestStatusArabic(req.status), style: GoogleFonts.tajawal(fontSize: 11)),
                                      backgroundColor: AppColors.orangeLight,
                                    ),
                                    const Spacer(),
                                    Text(_date(req.createdAt), style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
                                  ],
                                ),
                                Text(
                                  'Ø§Ù„ÙÙ†ÙŠ: ${tName != null && tName.isNotEmpty ? tName : 'Ù„Ù… ÙŠØªÙ… ØªØ¹ÙŠÙŠÙ† ÙÙ†ÙŠ Ø¨Ø¹Ø¯'}',
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.tajawal(fontSize: 13),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  (req.description ?? req.notes ?? '-'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton(
                                    onPressed: () => _showDetails(context, req, _techById),
                                    child: Text('Ø¹Ø±Ø¶ Ø§Ù„ØªÙØ§ØµÙŠÙ„', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _MyRequestsShimmer extends StatelessWidget {
  const _MyRequestsShimmer();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, _) => Container(
          height: 130,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

