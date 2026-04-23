import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/config/backend_orders_config.dart';
import '../../../../core/constants/order_status.dart';
import '../../../../core/services/backend_order_read_validator.dart';
import '../../../../core/services/backend_orders_client.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/session/backend_identity_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/safe_tracking_url.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/full_screen_image_viewer.dart';
import '../../../../core/utils/web_image_url.dart';

/// تفاصيل طلب من PostgreSQL عبر `GET /orders/:id`.
class AdminOrderDetailScreen extends StatefulWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends State<AdminOrderDetailScreen> {
  int _retryTick = 0;

  static (double, double)? _deliveryLatLng(Map<String, dynamic> o) {
    final loc = o['deliveryLocation'];
    if (loc == null) throw StateError('NULL_RESPONSE');
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

  Future<void> _openMap(double lat, double lng) async {
    final u = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    } on Object {
      debugPrint('[AdminOrderDetailScreen] _openMap failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر فتح الخرائط حالياً.', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  static bool _showShippingSection(String statusRaw) {
    final en = OrderStatus.toEnglish(statusRaw);
    return en == 'processing' || en == 'shipped' || en == 'delivered';
  }

  Future<Map<String, dynamic>?> _loadOrder() async {
    if (!BackendOrdersConfig.useBackendOrdersRead) throw StateError('NULL_RESPONSE');
    final raw = await BackendOrdersClient.instance.fetchOrderGet(widget.orderId);
    if (raw == null) throw StateError('NULL_RESPONSE');
    return BackendOrderReadValidator.backendOrderMap(raw);
  }

  @override
  Widget build(BuildContext context) {
    final uid = UserSession.currentUid;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBarBackButton(),
        title: Text('طلب ${widget.orderId}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        key: ValueKey<int>(_retryTick),
        future: _loadOrder(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.orange));
          }
          final o = snap.data;
          if (o == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('تعذر تحميل الطلب من الخادم.', style: GoogleFonts.tajawal()),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(() => _retryTick++),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }
          final items = o['items'] is List<dynamic>
              ? (o['items'] as List<dynamic>)
              : List<dynamic>.empty(growable: false);
          final billing = o['billing'] is Map ? Map<String, dynamic>.from(o['billing'] as Map) : <String, dynamic>{};
          final pair = _deliveryLatLng(o);
          final lat = pair?.$1;
          final lng = pair?.$2;
          final statusRaw = o['status']?.toString() ?? (throw StateError('NULL_RESPONSE'));
          final customerUid = o['customerUid']?.toString().trim() ?? (throw StateError('NULL_RESPONSE'));
          final showShip = _showShippingSection(statusRaw);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'الحالة: ${OrderStatus.toArabicForDisplay(o['status']?.toString() ?? (throw StateError('NULL_RESPONSE')))}',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
              ),
              Text(
                'الإجمالي: ${o['total'] ?? (throw StateError('NULL_RESPONSE'))} ${o['currency'] ?? (throw StateError('NULL_RESPONSE'))}',
                style: GoogleFonts.tajawal(),
              ),
              const SizedBox(height: 8),
              Text('العميل', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
              Text(
                '${billing['first_name'] ?? (throw StateError('NULL_RESPONSE'))} ${billing['last_name'] ?? (throw StateError('NULL_RESPONSE'))}'
                    .trim(),
                style: GoogleFonts.tajawal(),
              ),
              Text(
                billing['phone']?.toString() ?? (throw StateError('NULL_RESPONSE')),
                style: GoogleFonts.tajawal(fontSize: 13),
              ),
              Text(
                billing['email']?.toString() ?? (throw StateError('NULL_RESPONSE')),
                style: GoogleFonts.tajawal(fontSize: 13),
              ),
              Text(
                '${billing['address_1'] ?? (throw StateError('NULL_RESPONSE'))} — ${billing['city'] ?? (throw StateError('NULL_RESPONSE'))} — ${billing['country'] ?? (throw StateError('NULL_RESPONSE'))}',
                style: GoogleFonts.tajawal(fontSize: 13),
              ),
              if (lat != null && lng != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _openMap(lat, lng),
                  icon: const Icon(Icons.map_outlined),
                  label: Text('عرض الموقع على الخريطة', style: GoogleFonts.tajawal()),
                ),
              ],
              if (showShip && customerUid.isNotEmpty && uid.isNotEmpty) ...[
                const SizedBox(height: 20),
                _ShippingTrackingBlock(
                  key: ValueKey<Object?>(o['updatedAt']),
                  orderId: widget.orderId,
                  customerUid: customerUid,
                  orderData: o,
                  adminUid: uid,
                ),
              ],
              const SizedBox(height: 20),
              Text('المنتجات', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              ...items.map((raw) {
                if (raw is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(raw);
                final name = m['name']?.toString() ?? (throw StateError('NULL_RESPONSE'));
                final qty = (m['quantity'] as num?)?.toInt() ?? (throw StateError('INVALID_NUMERIC_DATA'));
                final price = m['price']?.toString() ?? (throw StateError('NULL_RESPONSE'));
                final imgs = m['images'] is List<dynamic>
                    ? (m['images'] as List<dynamic>)
                    : List<dynamic>.empty(growable: false);
                final img = imgs.isNotEmpty ? imgs.first.toString() : '';
                final unit = double.tryParse(price.replaceAll(RegExp(r'[^\d.]'), '')) ??
                    (throw StateError('INVALID_NUMERIC_DATA'));
                final line = unit * qty;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: img.isNotEmpty
                              ? () => openImageViewer(
                                    context,
                                    imageUrl: webSafeImageUrl(img),
                                    title: name,
                                  )
                              : null,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: img.isNotEmpty
                                ? Image.network(
                                    webSafeImageUrl(img),
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 72,
                                      height: 72,
                                      color: AppColors.border,
                                      child: const Icon(Icons.image_not_supported_outlined),
                                    ),
                                  )
                                : Container(
                                    width: 72,
                                    height: 72,
                                    color: AppColors.border,
                                    child: const Icon(Icons.inventory_2_outlined),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(name, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                              Text('الكمية: $qty', style: GoogleFonts.tajawal(fontSize: 13)),
                              Text('سعر الوحدة: $price', style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary)),
                              Text('الإجمالي: ${line.toStringAsFixed(2)}', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ShippingTrackingBlock extends StatefulWidget {
  const _ShippingTrackingBlock({
    super.key,
    required this.orderId,
    required this.customerUid,
    required this.orderData,
    required this.adminUid,
  });

  final String orderId;
  final String customerUid;
  final Map<String, dynamic> orderData;
  final String adminUid;

  @override
  State<_ShippingTrackingBlock> createState() => _ShippingTrackingBlockState();
}

class _ShippingTrackingBlockState extends State<_ShippingTrackingBlock> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _numCtrl;
  late final TextEditingController _companyCtrl;
  DateTime? _estimated;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final o = widget.orderData;
    _urlCtrl = TextEditingController(text: o['trackingUrl']?.toString() ?? (throw StateError('NULL_RESPONSE')));
    _numCtrl = TextEditingController(text: o['trackingNumber']?.toString() ?? (throw StateError('NULL_RESPONSE')));
    _companyCtrl = TextEditingController(text: o['shippingCompany']?.toString() ?? (throw StateError('NULL_RESPONSE')));
    final ets = o['estimatedDeliveryDate'];
    if (ets is String) {
      _estimated = DateTime.tryParse(ets);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _numCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _estimated ?? now.add(const Duration(days: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (d != null) setState(() => _estimated = d);
  }

  Future<void> _save(String? staffRole) async {
    final canEdit =
        PermissionService.canEditShippingTracking(staffRole ?? (throw StateError('NULL_RESPONSE')));
    if (!canEdit) return;
    final safeUrl = SafeTrackingUrl.sanitize(_urlCtrl.text);
    if (_urlCtrl.text.trim().isNotEmpty && safeUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('رابط التتبع غير صالح. استخدم رابط https فقط.', style: GoogleFonts.tajawal())),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'يُدار حفظ الشحن من الخادم — استخدم واجهة الطلبات في الـ API.',
              style: GoogleFonts.tajawal(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BackendIdentityController.instance,
      builder: (context, _) {
        final me = BackendIdentityController.instance.me;
        final role = me == null ? null : PermissionService.staffRoleFromUserData({'role': me.role});
        final canEdit =
            PermissionService.canEditShippingTracking(role ?? (throw StateError('NULL_RESPONSE')));

        return Card(
          color: AppColors.surfaceSecondary,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('معلومات الشحن', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  canEdit
                      ? 'تعديل بيانات التتبع (محليّاً) — الحفظ الدائم عبر الخادم.'
                      : 'عرض فقط — التعديل للمسؤول الكامل (full_admin).',
                  style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlCtrl,
                  readOnly: !canEdit,
                  decoration: InputDecoration(
                    labelText: 'رابط التتبع (https)',
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.tajawal(),
                  ),
                  style: GoogleFonts.tajawal(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _numCtrl,
                  readOnly: !canEdit,
                  decoration: InputDecoration(
                    labelText: 'رقم التتبع',
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.tajawal(),
                  ),
                  style: GoogleFonts.tajawal(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _companyCtrl,
                  readOnly: !canEdit,
                  decoration: InputDecoration(
                    labelText: 'شركة الشحن (مثل aramex، zajil، smsa)',
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.tajawal(),
                  ),
                  style: GoogleFonts.tajawal(),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('تاريخ التسليم المتوقع', style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _estimated == null ? 'لم يُحدَّد' : '${_estimated!.year}/${_estimated!.month}/${_estimated!.day}',
                    style: GoogleFonts.tajawal(),
                  ),
                  trailing: canEdit
                      ? IconButton(
                          onPressed: _saving ? null : _pickDate,
                          icon: const Icon(Icons.calendar_today_outlined),
                        )
                      : null,
                ),
                if (canEdit)
                  FilledButton(
                    onPressed: _saving ? null : () => _save(role),
                    child: _saving
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('حفظ معلومات الشحن', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
