import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/data/order_root_snapshot.dart';
import '../../../../core/data/repositories/order_repository.dart';
import '../../../../core/services/backend_orders_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';

/// شاشة تتبع التوصيل: حالة السائق، الوقت المتوقع، خط زمني، وإعادة المحاولة عند `no_driver_found`.
class OrderTrackingPage extends StatefulWidget {
  const OrderTrackingPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  Timer? _poll;
  Timer? _uiTick;
  bool _loading = true;
  String? _error;
  OrderRootSnapshot? _snap;
  bool _retryBusy = false;

  /// Updated after every successful fetch (including silent / pull).
  DateTime? _lastUpdatedAt;

  String? _lastKnownDeliveryStatus;
  String? _lastKnownDriverName;
  bool _primedChangeDetection = false;

  static const _timelineLabels = ['تم الطلب', 'تم التعيين', 'في الطريق', 'تم التسليم'];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_load(silent: true)));
    _uiTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _lastUpdatedAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _uiTick?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      final snap = await BackendOrderRepository.instance.fetchOrderRootSnapshot(widget.orderId.trim());
      if (!mounted) return;

      final data = snap.data;
      if (snap.exists && data != null) {
        final ds = _str(data, 'deliveryStatus');
        final dn = _str(data, 'driverName');
        if (_primedChangeDetection) {
          if (_lastKnownDeliveryStatus != null &&
              ds != null &&
              _lastKnownDeliveryStatus!.toLowerCase() != ds.toLowerCase()) {
            _maybeSnackForStatus(ds);
          }
          if (_lastKnownDriverName != null &&
              _lastKnownDriverName!.isNotEmpty &&
              dn != null &&
              dn.isNotEmpty &&
              _lastKnownDriverName != dn) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم تغيير السائق', style: GoogleFonts.tajawal())),
            );
          }
        }
        _lastKnownDeliveryStatus = ds;
        _lastKnownDriverName = dn;
        _primedChangeDetection = true;
        _lastUpdatedAt = DateTime.now();
      }

      setState(() {
        _snap = snap;
        _loading = false;
        if (!snap.exists) {
          _error = 'تعذّر تحميل تفاصيل الطلب.';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'حدث خطأ أثناء التحميل. اسحب للتحديث أو حاول لاحقاً.';
      });
    }
  }

  void _maybeSnackForStatus(String raw) {
    final s = raw.trim().toLowerCase();
    final String? msg = switch (s) {
      'on_the_way' => 'السائق في الطريق 🚚',
      'delivered' => 'تم التسليم',
      _ => null,
    };
    if (msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.tajawal())),
    );
  }

  String _relativeLastUpdateLabel() {
    final t = _lastUpdatedAt;
    if (t == null) return '';
    final sec = DateTime.now().difference(t).inSeconds;
    if (sec < 5) return 'تم التحديث الآن';
    if (sec == 1) return 'قبل ثانية واحدة';
    return 'قبل $sec ثواني';
  }

  String? _str(Map<String, dynamic>? m, String k) {
    if (m == null) return null;
    final v = m[k];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  int? _num(Map<String, dynamic>? m, String k) {
    if (m == null) return null;
    final v = m[k];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  DateTime? _parseIso(Map<String, dynamic>? m, String k) {
    final s = _str(m, k);
    if (s == null) return null;
    return DateTime.tryParse(s);
  }

  String? _fmtArClock(DateTime? dt) {
    if (dt == null) return null;
    final loc = dt.toLocal();
    final h24 = loc.hour;
    final m = loc.minute;
    final isPm = h24 >= 12;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${isPm ? 'م' : 'ص'}';
  }

  bool _isSearchingState(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    return s == 'pending' || s == 'assigned';
  }

  String _deliveryStatusArabic(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    switch (s) {
      case 'pending':
        return 'جاري البحث عن سائق';
      case 'assigned':
        return 'تم تعيين سائق';
      case 'accepted':
        return 'تم قبول الطلب من السائق';
      case 'on_the_way':
        return 'السائق في الطريق';
      case 'delivered':
        return 'تم التسليم';
      case 'no_driver_found':
        return 'لم يتم العثور على سائق حالياً';
      default:
        return s.isEmpty ? 'جاري تحديث حالة التوصيل' : (raw ?? '').trim();
    }
  }

  int _timelineCurrentIndex(String? deliveryStatus) {
    final s = (deliveryStatus ?? '').trim().toLowerCase();
    if (s == 'delivered') return 3;
    if (s == 'on_the_way') return 2;
    if (s == 'accepted' || s == 'assigned') return 1;
    if (s == 'no_driver_found' || s == 'pending' || s.isEmpty) return 0;
    return 0;
  }

  Future<void> _callDriver(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _confirmCallDriver(String? phone) async {
    final p = phone?.trim();
    if (p == null || p.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('اتصال', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text('هل تريد الاتصال بالسائق؟', textAlign: TextAlign.right, style: GoogleFonts.tajawal()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('لا', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
            child: Text('نعم', style: GoogleFonts.tajawal(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _callDriver(p);
    }
  }

  Future<void> _retryAssignment() async {
    if (_retryBusy) return;
    setState(() => _retryBusy = true);
    try {
      final ok = await BackendOrdersClient.instance.postOrderRetryAssignment(widget.orderId.trim());
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال طلب إعادة التعيين.', style: GoogleFonts.tajawal())),
        );
        await _load(silent: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّرت إعادة المحاولة. حاول لاحقاً.', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _retryBusy = false);
    }
  }

  List<String> _timelineDisplayLines(Map<String, dynamic> data) {
    final placed = _parseIso(data, 'receivedAt') ?? _parseIso(data, 'createdAt');
    final assigned = _parseIso(data, 'assignedAt');
    final way = _parseIso(data, 'onTheWayAt');
    final delivered = _parseIso(data, 'deliveredAt');
    final times = [_fmtArClock(placed), _fmtArClock(assigned), _fmtArClock(way), _fmtArClock(delivered)];
    return List<String>.generate(_timelineLabels.length, (i) {
      final t = times[i];
      if (t == null) return _timelineLabels[i];
      return '${_timelineLabels[i]} — $t';
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.orderId.trim();
    final data = _snap?.data;
    final deliveryStatus = _str(data, 'deliveryStatus');
    final driverPhone = _str(data, 'driverPhone');
    final driverNameResolved = _str(data, 'driverName');
    final eta = _num(data, 'etaMinutes');
    final canRetry = data?['canRetry'] as bool?;
    final isNoDriver = deliveryStatus != null && deliveryStatus.toLowerCase() == 'no_driver_found';
    final step = _timelineCurrentIndex(deliveryStatus);
    final showSearching = _isSearchingState(deliveryStatus);
    final timelineLines = data != null ? _timelineDisplayLines(data) : _timelineLabels;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: const AppBarBackButton(),
        title: Text('تتبع التوصيل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: AppColors.orange,
        onRefresh: () => _load(silent: true),
        child: _loading && _snap == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator(color: AppColors.orange)),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_lastUpdatedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _relativeLastUpdateLabel(),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.tajawal(color: AppColors.error)),
                    ),
                  if (data != null) ...[
                    if (showSearching)
                      Text(
                        '🔎 جاري البحث عن سائق...',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18),
                      )
                    else if (!isNoDriver)
                      Text(
                        _deliveryStatusArabic(deliveryStatus),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    if (eta != null && eta > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'الوصول خلال $eta دقيقة',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, color: AppColors.primaryOrange),
                      ),
                    ],
                    if (isNoDriver) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'لم يتم العثور على سائق حالياً',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (canRetry != false) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _retryBusy ? null : _retryAssignment,
                          icon: _retryBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.refresh),
                          label: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ],
                    ],
                    if (driverNameResolved != null) ...[
                      const SizedBox(height: 20),
                      Text('اسم السائق', textAlign: TextAlign.right, style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(driverNameResolved, textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                      if (driverPhone != null && driverPhone.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => _confirmCallDriver(driverPhone),
                          icon: const Icon(Icons.phone_in_talk_outlined),
                          label: Text('اتصال', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    Text('مسار التوصيل', textAlign: TextAlign.right, style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    _DeliveryTimeline(currentStep: step, labels: timelineLines),
                    const SizedBox(height: 24),
                    Text(
                      'رقم الطلب: $id',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.tajawal(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _DeliveryTimeline extends StatelessWidget {
  const _DeliveryTimeline({required this.currentStep, required this.labels});

  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (i) {
        final done = i < currentStep;
        final isCurrent = i == currentStep;
        final pending = i > currentStep;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: isCurrent ? 22 : 18,
                      height: isCurrent ? 22 : 18,
                      decoration: BoxDecoration(
                        color: pending ? AppColors.border : AppColors.orange,
                        shape: BoxShape.circle,
                        border: isCurrent ? Border.all(color: AppColors.orangeDark, width: 2) : null,
                        boxShadow: isCurrent
                            ? [BoxShadow(color: AppColors.orange.withOpacity(0.35), blurRadius: 6)]
                            : null,
                      ),
                      child: done
                          ? const Icon(Icons.check, size: 12, color: Colors.white)
                          : isCurrent
                              ? const SizedBox.shrink()
                              : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tajawal(
                        fontSize: 10,
                        color: pending ? AppColors.textSecondary : AppColors.orangeDark,
                        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (i != labels.length - 1)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 28),
                    color: i < currentStep ? AppColors.orange : AppColors.border,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
