import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/growth_analytics_service.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/home_page_shimmers.dart';
import '../../domain/models.dart';
import '../store_controller.dart';
import 'login_page.dart';
import 'order_tracking_screen.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, this.checkoutLines});

  /// إن وُجدت يُكمَّل الطلب لهذه الأسطر فقط (متجر واحد من السلة متعددة المتاجر).
  final List<CartItem>? checkoutLines;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'JO');
  double? _deliveryLat;
  double? _deliveryLng;
  String? _locationStatus;
  final _couponCtrl = TextEditingController();
  bool _checkoutStartLogged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (FirebaseAuth.instance.currentUser == null) {
        if (!mounted) return;
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        );
        return;
      }
      final store = context.read<StoreController>();
      final saved = await store.getSavedCheckoutInfo();
      if (saved != null && saved.hasAny) {
        if (_phone.text.trim().isEmpty) _phone.text = saved.phone;
        if (_address.text.trim().isEmpty) _address.text = saved.address1;
        if (_city.text.trim().isEmpty) _city.text = saved.city;
        if (saved.country.isNotEmpty) _country.text = saved.country;
        if (_firstName.text.trim().isEmpty) _firstName.text = saved.firstName;
        if (_lastName.text.trim().isEmpty) _lastName.text = saved.lastName;
        if (_email.text.trim().isEmpty && saved.email.isNotEmpty) _email.text = saved.email;
      }
      final p = store.profile;
      if (p != null) {
        if (_email.text.trim().isEmpty) {
          _email.text = p.email;
        }
        if (_phone.text.trim().isEmpty && p.phoneLocal != null && p.phoneLocal!.trim().isNotEmpty) {
          _phone.text = p.phoneLocal!.trim();
        }
        if (_address.text.trim().isEmpty && p.addressLine != null && p.addressLine!.trim().isNotEmpty) {
          _address.text = p.addressLine!.trim();
        }
        if (_city.text.trim().isEmpty && p.city != null && p.city!.trim().isNotEmpty) {
          _city.text = p.city!.trim();
        }
        if (p.country != null && p.country!.trim().isNotEmpty) {
          _country.text = p.country!.trim();
        }
        if (p.firstName != null && p.firstName!.trim().isNotEmpty && _firstName.text.trim().isEmpty) {
          _firstName.text = p.firstName!.trim();
        }
        if (p.lastName != null && p.lastName!.trim().isNotEmpty && _lastName.text.trim().isEmpty) {
          _lastName.text = p.lastName!.trim();
        }
        final name = p.fullName?.trim();
        if (name != null && name.isNotEmpty) {
          final parts = name.split(RegExp(r'\s+'));
          if (_firstName.text.trim().isEmpty && parts.isNotEmpty) {
            _firstName.text = parts.first;
          }
          if (_lastName.text.trim().isEmpty && parts.length > 1) {
            _lastName.text = parts.sublist(1).join(' ');
          }
        }
      }
      if (mounted) setState(() {});
      if (!_checkoutStartLogged) {
        _checkoutStartLogged = true;
        GrowthAnalyticsService.instance.logEvent(
          'checkout_start',
          payload: <String, Object?>{
            'items': (widget.checkoutLines ?? store.cart).length,
          },
          dedupKey: FirebaseAuth.instance.currentUser?.uid ?? 'guest',
          dedupWindow: const Duration(minutes: 1),
        );
      }
    });
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _city.dispose();
    _country.dispose();
    _couponCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreController>();
    final lines = widget.checkoutLines ?? store.cart;
    final subtotal = lines.fold<double>(0, (s, e) => s + e.totalPrice);
    final couponDiscount = store.discountAmount;
    final promotionsDiscount = store.promotionsDiscountAmount;
    final discount = couponDiscount + promotionsDiscount;
    final isDesktopWeb = kIsWeb && MediaQuery.of(context).size.width > 900;
    final textTheme = GoogleFonts.tajawalTextTheme(Theme.of(context).textTheme);

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: textTheme,
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: GoogleFonts.tajawal(color: AppColors.textSecondary),
          floatingLabelStyle: GoogleFonts.tajawal(color: AppColors.orange),
        ),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: const AppBarBackButton(),
          title: Text(
            'إتمام الطلب',
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, _) {
            final summaryCard = _buildOrderSummaryCard(
              context: context,
              store: store,
              lines: lines,
              subtotal: subtotal,
              couponDiscount: couponDiscount,
              promotionsDiscount: promotionsDiscount,
              discount: discount,
            );
            final formList = ListView(
          padding: const EdgeInsets.all(16),
          children: [
              if (!isDesktopWeb) summaryCard,
            const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('رمز الخصم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _couponCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: 'أدخل الكود',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
            FilledButton(
                            onPressed: () async {
                              final uid = FirebaseAuth.instance.currentUser?.uid;
                              if (uid == null) return;
                              final ok = await context.read<StoreController>().applyCoupon(_couponCtrl.text, uid);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok ? 'تم تطبيق الكود' : (store.errorMessage ?? 'تعذر تطبيق الكود'),
                                    style: GoogleFonts.tajawal(),
                                  ),
                                ),
                              );
                            },
                            child: Text('تطبيق', style: GoogleFonts.tajawal()),
                          ),
                        ],
                      ),
                      if (store.appliedCoupon != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'الكود المطبق: ${store.appliedCoupon!.code} • خصم ${store.formatMoney(discount)}',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: Colors.green.shade700),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => context.read<StoreController>().removeCoupon(),
                            child: Text('إزالة الخصم', style: GoogleFonts.tajawal(color: Colors.red)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      FilledButton.tonal(
                        onPressed: () async {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid == null) return;
                          final ok = await context.read<StoreController>().applyPromotions(uid);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? 'تم تحديث العروض المطبقة' : (store.errorMessage ?? 'تعذر تطبيق العروض'),
                                style: GoogleFonts.tajawal(),
                              ),
                            ),
                          );
                        },
                        child: Text('تطبيق العروض المتاحة', style: GoogleFonts.tajawal()),
                      ),
                      if (store.appliedPromotions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'العروض المطبقة: ${store.appliedPromotions.map((e) => e.name).join('، ')}',
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: Colors.green.shade700, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'بيانات التوصيل',
                style: GoogleFonts.tajawal(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _field(
                controller: _firstName,
                label: 'الاسم الأول',
              ),
              _field(
                controller: _lastName,
                label: 'اسم العائلة',
              ),
              _field(
                controller: _email,
                label: 'البريد الإلكتروني (اختياري)',
                keyboardType: TextInputType.emailAddress,
                requiredField: false,
              ),
              _field(
                controller: _phone,
                label: 'رقم الجوال',
                keyboardType: TextInputType.phone,
              ),
              _field(
                controller: _address,
                label: 'العنوان التفصيلي',
              ),
              _field(
                controller: _city,
                label: 'المدينة',
              ),
              _field(
                controller: _country,
                label: 'رمز الدولة (مثال: JO)',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: store.isLoading
                    ? null
                    : () async {
                        setState(() => _locationStatus = 'جاري تحديد الموقع…');
                        try {
                          var perm = await Geolocator.checkPermission();
                          if (perm == LocationPermission.denied) {
                            perm = await Geolocator.requestPermission();
                          }
                          if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
                            if (!context.mounted) return;
                            setState(() {
                              _locationStatus = 'لم يُمنح إذن الموقع';
                              _deliveryLat = null;
                              _deliveryLng = null;
                            });
                            return;
                          }
                          final pos = await Geolocator.getCurrentPosition();
                          if (!context.mounted) return;
                          setState(() {
                            _deliveryLat = pos.latitude;
                            _deliveryLng = pos.longitude;
                            _locationStatus = 'تم إرفاق الموقع مع الطلب';
                          });
                        } on Object {
                          if (!context.mounted) return;
                          setState(() => _locationStatus = 'تعذر تحديد الموقع');
                        }
                      },
                icon: const Icon(Icons.my_location_rounded, color: AppColors.orange),
                label: Text('إرفاق موقعي (GPS) مع الطلب', style: GoogleFonts.tajawal()),
              ),
              if (_locationStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _locationStatus!,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
              onPressed: store.isLoading
                  ? null
                  : () async {
                      if (!(_formKey.currentState?.validate() ?? false)) return;
                      final ok = await context.read<StoreController>().placeOrder(
                            firstName: _firstName.text.trim(),
                            lastName: _lastName.text.trim(),
                            email: _email.text.trim(),
                            phone: _phone.text.trim(),
                            address1: _address.text.trim(),
                            city: _city.text.trim(),
                            country: _country.text.trim(),
                                latitude: _deliveryLat,
                                longitude: _deliveryLng,
                                cartLines: widget.checkoutLines,
                              );
                          if (!context.mounted) return;
                          if (ok) {
                            final itemsCount = (widget.checkoutLines ?? store.cart).length;
                            GrowthAnalyticsService.instance.logEvent(
                              'order_complete',
                              payload: <String, Object?>{
                                'value': subtotal,
                                'items': itemsCount,
                              },
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم إرسال الطلب بنجاح. شكراً لثقتك بـ AmmarJo',
                                  style: GoogleFonts.tajawal(),
                                ),
                              ),
                            );
                            await _showShareReferralPrompt(context);
                            if (!context.mounted) return;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => const OrderTrackingScreen(),
                              ),
                            );
                          } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  store.errorMessage ?? 'تعذر إرسال الطلب. حاول مرة أخرى.',
                                  style: GoogleFonts.tajawal(),
                                ),
                              ),
                            );
                          }
                        },
                  child: store.isLoading
                      ? const InlineLightButtonShimmer(size: 24)
                      : Text(
                          'تأكيد الطلب',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                ),
              ),
            ],
          );
            if (!isDesktopWeb) return formList;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: formList),
                const SizedBox(width: 24),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                    child: summaryCard,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }

  Future<void> _showShareReferralPrompt(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;
    final referralCode = _buildReferralCode(uid);
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'شارك التطبيق وخذ خصم',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'كود الدعوة الخاص بك: $referralCode',
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: 'جرّب تطبيق AmmarJo واستخدم كود الدعوة: $referralCode',
                    ),
                  );
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم نسخ رسالة المشاركة', style: GoogleFonts.tajawal()),
                    ),
                  );
                  GrowthAnalyticsService.instance.logEvent(
                    'referral_share_copy',
                    payload: <String, Object?>{'referral_code': referralCode},
                  );
                },
                icon: const Icon(Icons.share_outlined),
                label: Text('نسخ رسالة المشاركة', style: GoogleFonts.tajawal()),
              ),
            ],
          ),
        );
      },
    );
  }

  String _buildReferralCode(String uid) {
    final clean = uid.replaceAll('-', '').toUpperCase();
    final core = clean.length >= 6 ? clean.substring(0, 6) : clean.padRight(6, 'X');
    return 'AMR$core';
  }

  Widget _buildOrderSummaryCard({
    required BuildContext context,
    required StoreController store,
    required List<CartItem> lines,
    required double subtotal,
    required double couponDiscount,
    required double promotionsDiscount,
    required double discount,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<StoreShippingComputation>(
          future: store.computeShippingForCartLines(lines, userCity: _city.text.trim()),
          builder: (context, snap) {
            final computedShipping = snap.data?.totalShipping ?? 0.0;
            final shipping = store.freeShippingByPromotion ? 0.0 : computedShipping;
            final beforeDiscount = subtotal + shipping;
            final grandTotal = (beforeDiscount - discount) < 0 ? 0.0 : (beforeDiscount - discount);
            final shippingLines = snap.data?.lines ?? const <StoreShippingLineCost>[];
            final uncovered = snap.data?.uncoveredStoreNames ?? const <String>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ملخص الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('مجموع المنتجات', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                    Text(store.formatMoney(subtotal), style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                ...shippingLines.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('توصيل ${e.storeName}', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                        Text(
                          e.shippingCost <= 0 ? 'مجاني' : store.formatMoney(e.shippingCost),
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('إجمالي الشحن', style: GoogleFonts.tajawal(color: AppColors.textSecondary)),
                    Text(
                      shipping <= 0 ? 'مجاني' : store.formatMoney(shipping),
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (uncovered.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'تنبيه: بعض المتاجر لا تغطي منطقتك (${uncovered.join('، ')})',
                      style: GoogleFonts.tajawal(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.right,
                    ),
                  ),
                const Divider(height: 18),
                if (couponDiscount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الخصم', style: GoogleFonts.tajawal(color: Colors.green.shade700)),
                        Text(
                          '- ${store.formatMoney(couponDiscount)}',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: Colors.green.shade700),
                        ),
                      ],
                    ),
                  ),
                if (promotionsDiscount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('خصم العروض', style: GoogleFonts.tajawal(color: Colors.green.shade700)),
                        Text(
                          '- ${store.formatMoney(promotionsDiscount)}',
                          style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, color: Colors.green.shade700),
                        ),
                      ],
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الإجمالي', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(
                      store.formatMoney(grandTotal),
                      style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.orange),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool requiredField = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        textDirection: TextDirection.rtl,
        validator: (v) {
          if (!requiredField) return null;
          if (v == null || v.trim().isEmpty) {
            return 'هذا الحقل مطلوب';
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}
