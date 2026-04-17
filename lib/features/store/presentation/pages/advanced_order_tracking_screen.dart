import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/order_status.dart';
import '../../../../core/data/order_root_snapshot.dart';
import '../../../../core/data/repositories/order_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/safe_tracking_url.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/data/repositories/customer_ops_repository.dart';

/// شاشة تتبع متقدّمة: خريطة خارجية، خط زمني، تاريخ التسليم المتوقع، ومشاركة رابط التتبع.
class AdvancedOrderTrackingScreen extends StatefulWidget {
  const AdvancedOrderTrackingScreen({super.key, required this.order});

  final TrackOrderItem order;

  @override
  State<AdvancedOrderTrackingScreen> createState() => _AdvancedOrderTrackingScreenState();
}

class _AdvancedOrderTrackingScreenState extends State<AdvancedOrderTrackingScreen> {
  Timer? _tick;
  Timer? _orderPoll;
  OrderRootSnapshot? _orderRoot;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.order.estimatedDeliveryDate != null) setState(() {});
    });
    final oid = widget.order.firebaseOrderId ?? widget.order.id;
    Future<void> poll() async {
      try {
        final snap = await BackendOrderRepository.instance.fetchOrderRootSnapshot(oid);
        if (mounted) setState(() => _orderRoot = snap);
      } on Object {
        /* non-debug: backend-only; keep last known */
      }
    }

    unawaited(poll());
    _orderPoll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(poll()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _orderPoll?.cancel();
    super.dispose();
  }

  Future<void> _openMaps(double lat, double lng) async {
    final u = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openTrackingLink() async {
    final raw = widget.order.trackingUrl;
    final u = SafeTrackingUrl.sanitize(raw);
    if (u == null) return;
    final uri = Uri.parse(u);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareTracking() async {
    final u = SafeTrackingUrl.sanitize(widget.order.trackingUrl);
    final id = widget.order.firebaseOrderId ?? widget.order.id;
    final text = u != null && u.isNotEmpty
        ? 'تتبع طلبي #$id\n$u'
        : 'طلبي #$id — حالة: ${OrderStatus.toArabicForDisplay(widget.order.status)}';
    await Share.share(text);
  }

  Future<void> _openWhatsAppShare() async {
    final u = SafeTrackingUrl.sanitize(widget.order.trackingUrl);
    final id = widget.order.firebaseOrderId ?? widget.order.id;
    final text = u != null && u.isNotEmpty
        ? 'تتبع طلبي #$id\n$u'
        : 'طلبي #$id — حالة: ${OrderStatus.toArabicForDisplay(widget.order.status)}';
    final wa = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(wa)) {
      await launchUrl(wa, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSmsShare() async {
    final u = SafeTrackingUrl.sanitize(widget.order.trackingUrl);
    final id = widget.order.firebaseOrderId ?? widget.order.id;
    final text = u != null && u.isNotEmpty
        ? 'تتبع طلبي #$id\n$u'
        : 'طلبي #$id';
    final sms = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(sms)) {
      await launchUrl(sms);
    }
  }

  String _countdownLabel(DateTime target) {
    final now = DateTime.now();
    if (!target.isAfter(now)) {
      return 'انتهى التاريخ المتوقع';
    }
    final diff = target.difference(now);
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (d > 0) return 'متبقٍ: $d يوم و $h ساعة';
    if (h > 0) return 'متبقٍ: $h ساعة و $m دقيقة';
    if (m > 0) return 'متبقٍ: $m دقيقة و $s ثانية';
    return 'متبقٍ: $s ثانية';
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final oid = o.firebaseOrderId ?? o.id;
    final statusEn = OrderStatus.toEnglish(o.status);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: const AppBarBackButton(),
        title: Text('تتبع الطلب #$oid', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'مشاركة',
            onPressed: _shareTracking,
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      ),
      body: !Firebase.apps.isNotEmpty
          ? const Center(child: Text('Firebase غير مهيأ'))
          : Builder(
              builder: (context) {
                double? lat;
                double? lng;
                final root = _orderRoot;
                if (root != null && root.exists) {
                  final d = root.data ?? {};
                  final loc = d['deliveryLocation'];
                  if (loc is Map) {
                    lat = (loc['latitude'] as num?)?.toDouble();
                    lng = (loc['longitude'] as num?)?.toDouble();
                  }
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _MapPreviewCard(
                      lat: lat ?? o.deliveryLatitude,
                      lng: lng ?? o.deliveryLongitude,
                      onOpenExternal: (la, ln) => _openMaps(la, ln),
                    ),
                    const SizedBox(height: 16),
                    if (SafeTrackingUrl.sanitize(o.trackingUrl) != null)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: _openTrackingLink,
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: Text('تتبع الشحن', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                      ),
                    if (SafeTrackingUrl.sanitize(o.trackingUrl) != null) const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openWhatsAppShare,
                            icon: const Icon(Icons.chat_rounded),
                            label: Text('واتساب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openSmsShare,
                            icon: const Icon(Icons.sms_outlined),
                            label: Text('رسالة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _shareTracking,
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text('مشاركة عامة', style: GoogleFonts.tajawal()),
                    ),
                    const SizedBox(height: 24),
                    Text('الخط الزمني', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
                    const SizedBox(height: 12),
                    _StatusTimeline(
                      createdAt: o.createdAt,
                      statusEnglish: statusEn,
                      updatedAt: o.updatedAt,
                    ),
                    const SizedBox(height: 24),
                    if (o.estimatedDeliveryDate != null) ...[
                      Text('التسليم المتوقع', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${o.estimatedDeliveryDate!.year}/${o.estimatedDeliveryDate!.month}/${o.estimatedDeliveryDate!.day}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.orange),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _countdownLabel(o.estimatedDeliveryDate!),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (o.trackingNumber != null && o.trackingNumber!.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('رقم التتبع: ${o.trackingNumber}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                    ],
                    if (o.shippingCompany != null && o.shippingCompany!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('شركة الشحن: ${o.shippingCompany}', style: GoogleFonts.tajawal()),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _MapPreviewCard extends StatelessWidget {
  const _MapPreviewCard({
    required this.lat,
    required this.lng,
    required this.onOpenExternal,
  });

  final double? lat;
  final double? lng;
  final void Function(double lat, double lng) onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final hasCoords = lat != null && lng != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 200,
            color: AppColors.surfaceSecondary,
            child: hasCoords
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Icon(Icons.map_rounded, size: 72, color: AppColors.orange.withValues(alpha: 0.35)),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_rounded, size: 48, color: AppColors.orange),
                            const SizedBox(height: 8),
                            Text(
                              '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}',
                              style: GoogleFonts.tajawal(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Text(
                      'لا يوجد موقع توصيل محفوظ لهذا الطلب',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(color: AppColors.textSecondary),
                    ),
                  ),
          ),
          if (hasCoords)
            ListTile(
              leading: const Icon(Icons.navigation_rounded, color: AppColors.orange),
              title: Text('فتح في خرائط Google', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              onTap: () => onOpenExternal(lat!, lng!),
            ),
        ],
      ),
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({
    required this.createdAt,
    required this.statusEnglish,
    this.updatedAt,
  });

  final DateTime createdAt;
  final String statusEnglish;
  final DateTime? updatedAt;

  int _step(String en) {
    switch (en) {
      case 'cancelled':
      case 'refunded':
      case 'failed':
        return -1;
      case 'processing':
        return 1;
      case 'shipped':
        return 2;
      case 'delivered':
      case 'completed':
        return 3;
      case 'pending':
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = _step(statusEnglish);
    const labels = ['قيد المراجعة', 'قيد التجهيز', 'تم الشحن', 'تم التوصيل'];
    final icons = [Icons.receipt_long_rounded, Icons.inventory_2_rounded, Icons.local_shipping_rounded, Icons.check_circle_rounded];
    final colors = [Colors.blueGrey, Colors.amber.shade800, AppColors.orange, Colors.green.shade700];

    return Column(
      children: List.generate(4, (i) {
        final done = cur >= 0 && i <= cur;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: done ? colors[i].withValues(alpha: 0.2) : AppColors.border.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(icons[i], color: done ? colors[i] : AppColors.textSecondary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labels[i],
                      style: GoogleFonts.tajawal(
                        fontWeight: done ? FontWeight.w800 : FontWeight.w500,
                        color: done ? AppColors.heading : AppColors.textSecondary,
                      ),
                    ),
                    if (i == 0)
                      Text(
                        '${createdAt.year}/${createdAt.month}/${createdAt.day} · ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    if (i == cur && updatedAt != null && i > 0)
                      Text(
                        'آخر تحديث: ${updatedAt!.year}/${updatedAt!.month}/${updatedAt!.day}',
                        style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
