import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/services/backend_orders_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../store/presentation/pages/login_page.dart';
import '../../store/presentation/store_controller.dart';
import '../data/driver_workbench_models.dart';
import 'driver_register_page.dart';
import '../widgets/driver_order_card.dart';

/// لوحة السائق — ويب/موبايل، تتصل بـ [BackendOrdersClient] (نفس عنوان الـ API للتطبيق).
class DriverDashboardPage extends StatefulWidget {
  const DriverDashboardPage({super.key});

  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> {
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();

  DriverWorkbenchData? _data;
  String? _error;
  /// إذا كان هناك مستخدم مسجّل قبل أول تحميل، نعرض مؤشراً فوراً لتفادي وميض واجهة فارغة.
  bool _loading = FirebaseAuth.instance.currentUser != null;
  String? _actionBusy; // orderId + action suffix
  Timer? _poll;
  Timer? _loc;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      _stopTimers();
      if (user == null) {
        if (mounted) {
          setState(() {
            _data = null;
            _error = null;
            _loading = false;
          });
        }
        return;
      }
      await _bootstrapDriver(user);
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stopTimers();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _stopTimers() {
    _poll?.cancel();
    _loc?.cancel();
    _poll = null;
    _loc = null;
  }

  void _scheduleTimers() {
    _stopTimers();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
    _loc = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_data?.driver != null) {
        unawaited(_pushLocation());
      }
    });
  }

  Future<void> _bootstrapDriver(User user) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _ensureRegistered(user);
    _scheduleTimers();
    await _load(silent: false);
  }

  Future<void> _ensureRegistered(User user) async {
    try {
      await BackendOrdersClient.instance.postDriverRegister(
        name: user.displayName,
        phone: user.phoneNumber,
      );
    } on Object {
      // قد يكون السائق مسجلاً مسبقاً أو فشل بلا أهمية للعرض الأولي
    }
  }

  Future<void> _load({required bool silent}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await BackendOrdersClient.instance.fetchDriverWorkbench();
      if (!mounted) return;
      final map = Map<String, dynamic>.from(raw ?? const <String, dynamic>{});
      setState(() {
        _data = DriverWorkbenchData.fromJson(map);
        _loading = false;
        _error = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'تعذر تحميل البيانات. تحقق من الشبكة، عنوان الـ API، أو صلاحية orders.write للسائقين.';
      });
    }
  }

  Future<void> _pushLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      Position? pos = await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition();
      await BackendOrdersClient.instance.postDriverLocation(lat: pos.latitude, lng: pos.longitude);
    } on Object {
      // صامت — لا نكدّر واجهة السائق بانقطاع الموقع
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await BackendOrdersClient.instance.postDriverStatus(status);
      await _load(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث الحالة', style: GoogleFonts.tajawal())),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث الحالة', style: GoogleFonts.tajawal())),
        );
      }
    }
  }

  Future<void> _runOrderAction(Future<dynamic> Function() fn, String busyKey) async {
    setState(() => _actionBusy = busyKey);
    try {
      await fn();
      await _load(silent: true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تنفيذ العملية', style: GoogleFonts.tajawal())),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = null);
    }
  }

  Future<void> _signInEmail(BuildContext context) async {
    final store = context.read<StoreController>();
    final ok = await store.signInWithEmailPassword(_emailCtrl.text, _pwCtrl.text);
    if (!mounted) return;
    if (!ok && store.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.errorMessage!, style: GoogleFonts.tajawal())),
      );
    }
  }

  String _statusLabel(String code) {
    switch (code.toLowerCase()) {
      case 'online':
        return 'متصل';
      case 'busy':
        return 'مشغول';
      case 'offline':
      default:
        return 'غير متصل';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Text('لوحة السائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: user == null ? _buildLogin(context) : _buildDashboard(context, user),
    );
  }

  Widget _buildLogin(BuildContext context) {
    final store = context.watch<StoreController>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'سجّل الدخول بحساب السائق (نفس Firebase للتطبيق).',
          textAlign: TextAlign.right,
          style: GoogleFonts.tajawal(fontSize: 15, height: 1.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            labelText: 'البريد الإلكتروني',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pwCtrl,
          obscureText: true,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            labelText: 'كلمة المرور',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: store.isLoading ? null : () => _signInEmail(context),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.orange,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: store.isLoading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('دخول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
        ),
        TextButton(
          onPressed: store.isLoading
              ? null
              : () {
                  Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
                },
          child: Text('الدخول برقم الهاتف وكلمة المرور', style: GoogleFonts.tajawal(color: AppColors.orange)),
        ),
      ],
    );
  }

  Widget _buildDashboard(BuildContext context, User user) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.tajawal(height: 1.5)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : () => _load(silent: false),
                child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    final d = _data;
    final onboarding = d?.onboarding ?? const DriverOnboardingInfo(status: 'none');
    final profile = d?.driver;
    final assignedOrders = d?.assignedOrders;
    final historyOrders = d?.history;
    final assignedEmpty = assignedOrders == null || assignedOrders.isEmpty;
    final historyEmpty = historyOrders == null || historyOrders.isEmpty;

    if (onboarding.status == 'pending') {
      return RefreshIndicator(
        onRefresh: () => _load(silent: false),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.hourglass_top_rounded, size: 56, color: AppColors.orange.withValues(alpha: 0.9)),
            const SizedBox(height: 16),
            Text(
              'حسابك قيد المراجعة',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'بعد موافقة الإدارة ستُفعَّل لوحة السائق تلقائياً.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : () => _load(silent: false),
              child: Text('تحديث الحالة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    if (onboarding.status == 'rejected') {
      return RefreshIndicator(
        onRefresh: () => _load(silent: false),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.cancel_outlined, size: 56, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'لم تتم الموافقة على طلب الانضمام',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'يمكنك تقديم طلب جديد مع بيانات محدّثة.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const DriverRegisterPage()),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              child: Text('إعادة التقديم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }

    if (profile == null && onboarding.status == 'none') {
      return RefreshIndicator(
        onRefresh: () => _load(silent: false),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.local_shipping_outlined, size: 56, color: AppColors.orange.withValues(alpha: 0.9)),
            const SizedBox(height: 16),
            Text(
              'انضم كسائق',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'أرسل طلباً مع صورة الهوية. بعد الموافقة يمكنك استلام الطلبات.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const DriverRegisterPage()),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange, minimumSize: const Size.fromHeight(48)),
              child: Text('تسجيل كسائق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }

    if (profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'جاري مزامنة حساب السائق…',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(silent: false),
                child: Text('إعادة المحاولة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    }

    final snap = d!;
    return RefreshIndicator(
      onRefresh: () => _load(silent: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('الحالة', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            _statusLabel(profile.status),
            style: GoogleFonts.tajawal(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip('online', 'متصل', profile.status),
              _statusChip('busy', 'مشغول', profile.status),
              _statusChip('offline', 'غير متصل', profile.status),
            ],
          ),
          const SizedBox(height: 20),
          Text('الطلب النشط', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (snap.activeOrder == null)
            Text('لا يوجد طلب نشط', style: GoogleFonts.tajawal(color: AppColors.textSecondary))
          else ...[
            DriverOrderCard(order: snap.activeOrder!),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _actionBusy != null
                        ? null
                        : () => _runOrderAction(
                              () async {
                                await BackendOrdersClient.instance.postDriverOnTheWay(snap.activeOrder!.orderId);
                              },
                              '${snap.activeOrder!.orderId}-way',
                            ),
                    icon: const Icon(Icons.local_shipping_outlined, size: 20),
                    label: Text('في الطريق', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _actionBusy != null
                        ? null
                        : () => _runOrderAction(
                              () async {
                                await BackendOrdersClient.instance.postDriverCompleteOrder(snap.activeOrder!.orderId);
                              },
                              '${snap.activeOrder!.orderId}-done',
                            ),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: Text('تم التسليم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('طلبات متاحة (معيّنة لك)', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              if (_loading && _data != null)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (assignedEmpty)
            Text('لا توجد طلبات معلّقة', style: GoogleFonts.tajawal(color: AppColors.textSecondary))
          else
            ...snap.assignedOrders.map((o) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    DriverOrderCard(order: o),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _actionBusy != null
                                ? null
                                : () => _runOrderAction(
                                      () async {
                                        await BackendOrdersClient.instance.postDriverAcceptOrder(o.orderId);
                                      },
                                      '${o.orderId}-acc',
                                    ),
                            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                            child: Text('قبول', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _actionBusy != null
                                ? null
                                : () => _runOrderAction(
                                      () async {
                                        await BackendOrdersClient.instance.postDriverRejectOrder(o.orderId);
                                      },
                                      '${o.orderId}-rej',
                                    ),
                            child: Text('رفض', style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),
          Text('سجل التسليم', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (historyEmpty)
            Text('لا يوجد سجل بعد', style: GoogleFonts.tajawal(color: AppColors.textSecondary))
          else
            ...snap.history.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DriverOrderCard(order: o, dense: true),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            user.email ?? user.uid,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String value, String label, String current) {
    final selected = current.toLowerCase() == value;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
      selected: selected,
      onSelected: (_) => _setStatus(value),
      selectedColor: AppColors.lightOrange,
      labelStyle: GoogleFonts.tajawal(color: selected ? AppColors.orange : AppColors.textPrimary),
    );
  }
}
