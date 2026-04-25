import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/store_repository.dart';
import '../../../../core/session/user_session.dart';
import '../../../../core/session/backend_identity_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../admin/presentation/pages/admin_dashboard_screen.dart';
import '../../../store_owner/presentation/store_owner_dashboard.dart';
import '../../../wholesale/presentation/pages/wholesale_apply_page.dart';
import '../../../wholesale/presentation/pages/wholesale_marketplace_page.dart';
import '../../../support/presentation/open_support_chat.dart';
import '../../../maintenance/presentation/pages/my_service_requests_page.dart';
import '../../../stores/domain/store_model.dart';
import '../../../tenders/presentation/pages/my_tenders_screen.dart';
import '../pages/customer_delivery_settings_page.dart';
import '../pages/my_orders_page.dart';
import '../pages/order_tracking_screen.dart';
import '../pages/smart_quantity_calculator_page.dart';
import '../pages/wallet_screen.dart';
import '../store_controller.dart';

/// قائمة جانبية — طلبات، أدوات، دعم، صفحات قانونية، لوحات التحكم.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _navigate(BuildContext context, Widget page) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _popThen(BuildContext context, VoidCallback fn) {
    Navigator.pop(context);
    // Avoid route push during drawer pointer/mouse update on web.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      fn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    color: AppColors.orange,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'القائمة',
                    style: GoogleFonts.tajawal(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _AppDrawerBody(
                navigate: _navigate,
                popThen: _popThen,
                drawerItem: _drawerItem,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color? color,
  }) {
    final c = color ?? const Color(0xFF1A1A2E);
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(
        title,
        style: GoogleFonts.tajawal(fontWeight: FontWeight.w500, color: c),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: GoogleFonts.tajawal(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            )
          : null,
      dense: true,
      horizontalTitleGap: 8,
      onTap: onTap,
    );
  }
}

/// محتوى القائمة حسب الدور: أدمن / تاجر جملة / صاحب متجر / عميل.
class _AppDrawerBody extends StatelessWidget {
  const _AppDrawerBody({
    required this.navigate,
    required this.popThen,
    required this.drawerItem,
  });

  final void Function(BuildContext context, Widget page) navigate;
  final void Function(BuildContext context, VoidCallback fn) popThen;

  final Widget Function(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color? color,
  })
  drawerItem;

  List<Widget> _legal(BuildContext context) => [
    drawerItem(
      context,
      icon: Icons.info_outline,
      title: 'من نحن',
      onTap: () =>
          popThen(context, () => Navigator.of(context).pushNamed('/about')),
    ),
    drawerItem(
      context,
      icon: Icons.privacy_tip_outlined,
      title: 'سياسة الخصوصية',
      onTap: () =>
          popThen(context, () => Navigator.of(context).pushNamed('/privacy')),
    ),
    drawerItem(
      context,
      icon: Icons.article_outlined,
      title: 'شروط الاستخدام',
      onTap: () =>
          popThen(context, () => Navigator.of(context).pushNamed('/terms')),
    ),
  ];

  /// زر انضمام كتاجر جملة — لأي مستخدم مسجّل ليس بدور wholesaler.
  List<Widget> _joinWholesaleBlocks(
    BuildContext context,
    String role,
    String storeType,
  ) {
    if (role != 'customer') {
      return const <Widget>[];
    }
    return <Widget>[
      const Divider(indent: 16, endIndent: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFE65100)],
            ),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: ListTile(
            leading: const Icon(
              Icons.store_mall_directory_outlined,
              color: Colors.white,
            ),
            title: Text(
              'انضم كتاجر جملة',
              style: GoogleFonts.tajawal(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              'افتح متجرك بالجملة',
              style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 11),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white,
              size: 14,
            ),
            onTap: () => popThen(
              context,
              () => navigate(context, const WholesaleApplyPage()),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _customerCore(BuildContext context) => [
    drawerItem(
      context,
      icon: Icons.receipt_long_outlined,
      title: 'طلباتي',
      onTap: () =>
          popThen(context, () => navigate(context, const MyOrdersPage())),
    ),
    drawerItem(
      context,
      icon: Icons.local_shipping_outlined,
      title: 'تتبع الطلب',
      onTap: () => popThen(
        context,
        () => navigate(context, const OrderTrackingScreen()),
      ),
    ),
    drawerItem(
      context,
      icon: Icons.home_repair_service_outlined,
      title: 'خدماتي',
      subtitle: 'طلبات الخدمة والصيانة',
      onTap: () => popThen(
        context,
        () => navigate(context, const MyServiceRequestsPage()),
      ),
    ),
    drawerItem(
      context,
      icon: Icons.gavel_outlined,
      title: 'مناقصاتي',
      onTap: () =>
          popThen(context, () => navigate(context, const MyTendersScreen())),
    ),
    drawerItem(
      context,
      icon: Icons.calculate_outlined,
      title: 'حاسبة الكميات',
      onTap: () => popThen(
        context,
        () => navigate(context, const SmartQuantityCalculatorPage()),
      ),
    ),
    drawerItem(
      context,
      icon: Icons.stars_outlined,
      title: 'نقاطي',
      onTap: () =>
          popThen(context, () => navigate(context, const WalletScreen())),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final uid = authSnap.data?.uid;
        if (uid == null) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              ..._legal(context),
              const Divider(indent: 16, endIndent: 16),
              drawerItem(
                context,
                icon: Icons.login_rounded,
                title: 'سجّل الدخول من «حسابي»',
                onTap: () => Navigator.pop(context),
                color: AppColors.textSecondary,
              ),
            ],
          );
        }

        return _buildSignedInDrawer(context, uid);
      },
    );
  }

  Widget _buildSignedInDrawer(BuildContext context, String uid) {
    return ListenableBuilder(
      listenable: BackendIdentityController.instance,
      builder: (context, _) {
        final me = BackendIdentityController.instance.me;
        final role = me?.role.trim() ?? '';
        final storeType = me?.storeType?.trim() ?? '';
        final showAdmin = UserSession.role == 'admin';
        final roleResolved = role.isNotEmpty ? role : 'customer';
        final storeTypeResolved = storeType;

        if (showAdmin) {
          return ListView(
            key: const ValueKey<String>('drawer-admin'),
            padding: EdgeInsets.zero,
            children: [
              drawerItem(
                context,
                icon: Icons.dashboard_outlined,
                title: 'لوحة التحكم الشاملة',
                color: AppColors.navy,
                onTap: () => popThen(
                  context,
                  () => navigate(context, const AdminDashboardScreen()),
                ),
              ),
              ..._joinWholesaleBlocks(context, roleResolved, storeTypeResolved),
              const Divider(indent: 16, endIndent: 16),
              ..._legal(context),
              const Divider(indent: 16, endIndent: 16),
              drawerItem(
                context,
                icon: Icons.logout,
                title: 'تسجيل الخروج',
                color: Colors.red,
                onTap: () async {
                  Navigator.pop(context);
                  await context.read<StoreController>().logout();
                },
              ),
              const SizedBox(height: 20),
            ],
          );
        }

        if (roleResolved == 'driver') {
          return ListView(
            key: const ValueKey<String>('drawer-driver'),
            padding: EdgeInsets.zero,
            children: [
              drawerItem(
                context,
                icon: Icons.delivery_dining_outlined,
                title: 'لوحة السائق',
                color: const Color(0xFFFF6B00),
                onTap: () => popThen(
                  context,
                  () => Navigator.of(context).pushNamed('/driver'),
                ),
              ),
              const Divider(indent: 16, endIndent: 16),
              drawerItem(
                context,
                icon: Icons.support_agent_outlined,
                title: 'احصل على مساعدة',
                color: const Color(0xFFFF6B00),
                onTap: () => popThen(context, () => openSupportChat(context)),
              ),
              const Divider(indent: 16, endIndent: 16),
              ..._legal(context),
              const Divider(indent: 16, endIndent: 16),
              drawerItem(
                context,
                icon: Icons.logout,
                title: 'تسجيل الخروج',
                color: Colors.red,
                onTap: () async {
                  Navigator.pop(context);
                  await context.read<StoreController>().logout();
                },
              ),
              const SizedBox(height: 20),
            ],
          );
        }

        final children = <Widget>[
          ..._customerCore(context),
          const Divider(indent: 16, endIndent: 16),
          drawerItem(
            context,
            icon: Icons.support_agent_outlined,
            title: 'احصل على مساعدة',
            color: const Color(0xFFFF6B00),
            onTap: () => popThen(context, () => openSupportChat(context)),
          ),
          ..._joinWholesaleBlocks(context, roleResolved, storeTypeResolved),
          drawerItem(
            context,
            icon: Icons.location_on_outlined,
            title: 'تعديل مكان التوصيل',
            onTap: () => popThen(
              context,
              () => navigate(context, const CustomerDeliverySettingsPage()),
            ),
          ),
        ];

        if (roleResolved == 'store_owner') {
          final storeId = me?.storeId?.trim() ?? '';
          children.add(const Divider(indent: 16, endIndent: 16));
          children.add(
            _StoreOwnerStoreTile(
              key: ValueKey<String>('owner-store-$storeId'),
              storeId: storeId,
              navigate: navigate,
              popThen: popThen,
              drawerItem: drawerItem,
            ),
          );
          if (storeTypeResolved == 'construction_store') {
            children.add(
              drawerItem(
                context,
                icon: Icons.warehouse_rounded,
                title: 'سوق الجملة',
                color: const Color(0xFFFF6B00),
                onTap: () => popThen(
                  context,
                  () => navigate(context, const WholesaleMarketplacePage()),
                ),
              ),
            );
          }
        }

        if (roleResolved == 'customer') {
          children.addAll([
            const Divider(indent: 16, endIndent: 16),
            drawerItem(
              context,
              icon: Icons.delivery_dining_outlined,
              title: 'انضم كسائق توصيل',
              color: const Color(0xFFFF6B00),
              onTap: () => popThen(
                context,
                () => Navigator.of(context).pushNamed('/driver/register'),
              ),
            ),
          ]);
        }

        children.addAll([
          const Divider(indent: 16, endIndent: 16),
          ..._legal(context),
          const Divider(indent: 16, endIndent: 16),
          drawerItem(
            context,
            icon: Icons.logout,
            title: 'تسجيل الخروج',
            color: Colors.red,
            onTap: () async {
              Navigator.pop(context);
              await context.read<StoreController>().logout();
            },
          ),
          const SizedBox(height: 20),
        ]);

        return ListView(
          key: ValueKey<String>('drawer-user-$roleResolved-$storeTypeResolved'),
          padding: EdgeInsets.zero,
          children: children,
        );
      },
    );
  }
}

class _StoreOwnerStoreTile extends StatefulWidget {
  const _StoreOwnerStoreTile({
    super.key,
    required this.storeId,
    required this.navigate,
    required this.popThen,
    required this.drawerItem,
  });

  final String storeId;
  final void Function(BuildContext context, Widget page) navigate;
  final void Function(BuildContext context, VoidCallback fn) popThen;
  final Widget Function(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color? color,
  })
  drawerItem;

  @override
  State<_StoreOwnerStoreTile> createState() => _StoreOwnerStoreTileState();
}

class _StoreOwnerStoreTileState extends State<_StoreOwnerStoreTile> {
  Future<FeatureState<StoreModel>>? _storeFuture;

  @override
  void initState() {
    super.initState();
    _primeFuture();
  }

  @override
  void didUpdateWidget(covariant _StoreOwnerStoreTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) {
      _primeFuture();
    }
  }

  void _primeFuture() {
    if (widget.storeId.isEmpty) {
      _storeFuture = null;
      return;
    }
    _storeFuture = context.read<StoreRepository>().fetchStoreDocument(
      widget.storeId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_storeFuture == null) return const SizedBox.shrink();
    return FutureBuilder<FeatureState<StoreModel>>(
      future: _storeFuture,
      builder: (context, storeSnap) {
        if (storeSnap.hasError) return const SizedBox.shrink();
        final state = storeSnap.data;
        if (state is! FeatureSuccess<StoreModel>) {
          return const SizedBox.shrink();
        }
        final store = state.data;
        final approved = store.status == 'approved';
        if (!approved) return const SizedBox.shrink();
        return widget.drawerItem(
          context,
          icon: Icons.store_outlined,
          title: 'لوحة تحكم متجري',
          color: const Color(0xFFFF6B00),
          onTap: () => widget.popThen(
            context,
            () => widget.navigate(context, const StoreOwnerDashboard()),
          ),
        );
      },
    );
  }
}
