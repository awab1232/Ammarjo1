import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ammar_store/core/session/user_session.dart';

import '../../../../core/contracts/feature_state.dart';
import '../../../../core/session/backend_identity_controller.dart';
import '../../../../core/services/permission_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../sections/admin_banner_manager_section.dart';
import '../sections/admin_categories_section.dart';
import '../sections/admin_commissions_section.dart';
import '../sections/admin_tech_specialties_section.dart';
import '../sections/admin_home_tools_stores_section.dart';
import '../sections/admin_migration_hub_section.dart';
import '../sections/admin_orders_section.dart';
import '../sections/admin_technicians_section.dart';
import '../sections/admin_wallet_section.dart';
import '../sections/admin_service_requests_section.dart';
import '../sections/admin_reports_section.dart';
import '../sections/admin_store_categories_section.dart';
import '../sections/admin_support_chats_section.dart';
import '../sections/admin_wholesale_management_section.dart';
import '../sections/admin_reviews_section.dart';
import '../sections/admin_analytics_section.dart';
import '../sections/admin_tenders_section.dart';
import '../sections/admin_tender_commissions_section.dart';
import '../sections/admin_blog_banners_section.dart';
import '../../data/admin_notification_repository.dart';
import '../sections/admin_sessions_section.dart';
import '../../../store/presentation/pages/main_navigation_page.dart';
import 'admin_audit_log_screen.dart';
import 'admin_delivery_dashboard_page.dart';
import 'admin_driver_requests_page.dart';
import 'admin_notifications_screen.dart';
import 'admin_overview_screen.dart';
import 'admin_products_screen.dart';
import 'admin_promotions_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_stores_screen.dart';
import 'admin_users_screen.dart';

/// لوحة تحكم إدارية: أقسام، تخصصات فنيين، بانرات، منتجات، طلبات، …
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminNavItem {
  const _AdminNavItem({
    required this.index,
    required this.icon,
    required this.labelAr,
  });
  final int index;
  final IconData icon;
  final String labelAr;
}

class _AdminNavGroup {
  const _AdminNavGroup({required this.titleAr, required this.items});
  final String titleAr;
  final List<_AdminNavItem> items;
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _index = 0;

  /// يمنع استدعاء [WidgetsBinding.addPostFrameCallback] في كل إعادة بناء (كان يسبب ضغطاً على الواجهة).
  String? _lastNavSyncKey;

  @override
  void initState() {
    super.initState();
    debugPrint('📊 AdminDashboardScreen mounted');
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    if (!UserSession.isLoggedIn || UserSession.currentUid.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const MainNavigationPage()),
          (_) => false,
        );
      });
      return;
    }
    void redirectToHome() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const MainNavigationPage()),
          (_) => false,
        );
      });
    }

    try {
      await BackendIdentityController.instance.refresh();
      final role = BackendIdentityController.instance.me?.role ?? '';
      final normalized = PermissionService.normalizeRole(role);
      if (normalized != PermissionService.roleAdmin && normalized != PermissionService.roleSystemInternal) {
        if (!mounted) return;
        redirectToHome();
      }
    } on Object {
      debugPrint('AdminDashboardScreen: role check failed — redirecting');
      if (!mounted) return;
      redirectToHome();
    }
  }

  /// لوحة الإدارة **كاملة** — يُسمح بالوصول للمستخدمين ذوي الدور `admin` أو `system_internal` فقط من `/auth/me`.
  bool _canAccessAdminDashboard(Map<String, dynamic>? data, String uid) {
    if (uid.isEmpty) return false;
    if (!BackendIdentityController.instance.isBackendFullAdmin) return false;
    final role = BackendIdentityController.instance.me?.role;
    final normalized = PermissionService.normalizeRole(role);
    return normalized == PermissionService.roleAdmin || normalized == PermissionService.roleSystemInternal;
  }

  List<_AdminNavGroup> _filteredNavGroups(String role) {
    return _navGroups
        .map((g) {
          final items = g.items
              .where(
                (e) => PermissionService.canAccessAdminNavIndex(e.index, role),
              )
              .toList();
          return _AdminNavGroup(titleAr: g.titleAr, items: items);
        })
        .where((g) => g.items.isNotEmpty)
        .toList();
  }

  void _syncNavIndexIfNeeded(String role) {
    if (PermissionService.canAccessAdminNavIndex(_index, role)) return;
    for (var i = 0; i < _titles.length; i++) {
      if (PermissionService.canAccessAdminNavIndex(i, role)) {
        setState(() => _index = i);
        return;
      }
    }
  }

  void _maybeScheduleNavSync({
    required String? uid,
    required Map<String, dynamic>? userData,
    required String role,
  }) {
    if (uid == null || uid.isEmpty) return;
    final roleStr = userData?['role']?.toString() ?? '';
    final key = '$uid|$roleStr';
    if (_lastNavSyncKey == key) return;
    _lastNavSyncKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncNavIndexIfNeeded(role);
    });
  }

  /// مجموعات التنقل (مثل Vercel): تقليل الازدحام في الشريط الجانبي.
  static const _navGroups = <_AdminNavGroup>[
    _AdminNavGroup(
      titleAr: 'نظرة عامة',
      items: <_AdminNavItem>[
        _AdminNavItem(
          index: 0,
          icon: Icons.space_dashboard_outlined,
          labelAr: 'لوحة المؤشرات',
        ),
      ],
    ),
    _AdminNavGroup(
      titleAr: 'النظام والبيانات',
      items: <_AdminNavItem>[
        _AdminNavItem(
          index: 1,
          icon: Icons.hub_outlined,
          labelAr: 'Migration Hub',
        ),
        _AdminNavItem(
          index: 17,
          icon: Icons.fact_check_outlined,
          labelAr: 'سجل التدقيق',
        ),
        _AdminNavItem(
          index: 13,
          icon: Icons.account_balance_wallet_outlined,
          labelAr: 'المحفظة',
        ),
        _AdminNavItem(
          index: 14,
          icon: Icons.local_shipping_outlined,
          labelAr: 'الشحن',
        ),
      ],
    ),
    _AdminNavGroup(
      titleAr: 'التجارة والمبيعات',
      items: <_AdminNavItem>[
        _AdminNavItem(
          index: 7,
          icon: Icons.receipt_long_outlined,
          labelAr: 'الطلبات',
        ),
        _AdminNavItem(
          index: 36,
          icon: Icons.delivery_dining_outlined,
          labelAr: 'إدارة التوصيل',
        ),
        _AdminNavItem(
          index: 37,
          icon: Icons.how_to_reg_outlined,
          labelAr: 'طلبات السائقين',
        ),
        _AdminNavItem(
          index: 6,
          icon: Icons.inventory_2_outlined,
          labelAr: 'المنتجات',
        ),
        _AdminNavItem(
          index: 3,
          icon: Icons.category_outlined,
          labelAr: 'الأقسام',
        ),
        _AdminNavItem(
          index: 9,
          icon: Icons.store_mall_directory_outlined,
          labelAr: 'طلبات المتاجر',
        ),
        _AdminNavItem(
          index: 10,
          icon: Icons.home_repair_service_outlined,
          labelAr: 'متاجر الأدوات المنزلية',
        ),
        _AdminNavItem(
          index: 12,
          icon: Icons.percent_outlined,
          labelAr: 'العمولات',
        ),
        _AdminNavItem(
          index: 19,
          icon: Icons.discount_outlined,
          labelAr: 'أكواد الخصم',
        ),
        _AdminNavItem(
          index: 20,
          icon: Icons.approval_outlined,
          labelAr: 'طلبات تسجيل جملة',
        ),
        _AdminNavItem(
          index: 21,
          icon: Icons.warehouse_outlined,
          labelAr: 'تجار الجملة',
        ),
        _AdminNavItem(
          index: 15,
          icon: Icons.grid_view_rounded,
          labelAr: 'تصنيفات المتاجر',
        ),
        _AdminNavItem(
          index: 29,
          icon: Icons.account_tree_outlined,
          labelAr: 'الأقسام الفرعية',
        ),
        _AdminNavItem(
          index: 30,
          icon: Icons.dashboard_customize_outlined,
          labelAr: 'الأقسام الرئيسية',
        ),
        _AdminNavItem(
          index: 31,
          icon: Icons.star_outline_rounded,
          labelAr: 'المتاجر المميزة',
        ),
        _AdminNavItem(
          index: 32,
          icon: Icons.trending_up_rounded,
          labelAr: 'Boost المنتجات',
        ),
        _AdminNavItem(
          index: 33,
          icon: Icons.tune_rounded,
          labelAr: 'إعدادات العمولة العامة',
        ),
        _AdminNavItem(
          index: 34,
          icon: Icons.storefront_outlined,
          labelAr: 'أنواع المتاجر',
        ),
        _AdminNavItem(
          index: 22,
          icon: Icons.reviews_outlined,
          labelAr: 'المراجعات',
        ),
        _AdminNavItem(
          index: 26,
          icon: Icons.gavel_outlined,
          labelAr: 'المناقصات',
        ),
        _AdminNavItem(
          index: 27,
          icon: Icons.request_quote_outlined,
          labelAr: 'عمولات المناقصات',
        ),
      ],
    ),
    _AdminNavGroup(
      titleAr: 'المحتوى والعرض',
      items: <_AdminNavItem>[
        _AdminNavItem(
          index: 5,
          icon: Icons.view_carousel_outlined,
          labelAr: 'البانرات',
        ),
        _AdminNavItem(
          index: 28,
          icon: Icons.web_asset_outlined,
          labelAr: 'بنرات المدونة',
        ),
      ],
    ),
    _AdminNavGroup(
      titleAr: 'العملاء والفنيون',
      items: <_AdminNavItem>[
        _AdminNavItem(
          index: 2,
          icon: Icons.people_outline,
          labelAr: 'المستخدمون',
        ),
        _AdminNavItem(
          index: 8,
          icon: Icons.engineering_outlined,
          labelAr: 'الفنيون',
        ),
        _AdminNavItem(index: 18, icon: Icons.build, labelAr: 'طلبات الخدمة'),
        _AdminNavItem(
          index: 4,
          icon: Icons.home_repair_service_outlined,
          labelAr: 'تخصصات الفنيين',
        ),
      ],
    ),
    _AdminNavGroup(
      titleAr: 'الدعم والسلامة',
      items: <_AdminNavItem>[
        _AdminNavItem(
          index: 11,
          icon: Icons.flag_outlined,
          labelAr: 'البلاغات',
        ),
        _AdminNavItem(
          index: 16,
          icon: Icons.support_agent_rounded,
          labelAr: 'دعم العملاء',
        ),
        _AdminNavItem(
          index: 35,
          icon: Icons.devices_rounded,
          labelAr: 'الأجهزة والجلسات',
        ),
      ],
    ),
    _AdminNavGroup(
      titleAr: 'التقارير',
      items: <_AdminNavItem>[
        _AdminNavItem(
          index: 23,
          icon: Icons.analytics_outlined,
          labelAr: 'التقارير والتحليلات',
        ),
      ],
    ),
  ];

  static const _titles = <String>[
    'لوحة المؤشرات',
    'Migration Hub',
    'المستخدمون',
    'الأقسام',
    'تخصصات الفنيين',
    'البانرات',
    'المنتجات',
    'الطلبات',
    'الفنيون',
    'طلبات المتاجر',
    'متاجر الأدوات المنزلية',
    'البلاغات',
    'العمولات',
    'المحفظة',
    'الشحن',
    'تصنيفات المتاجر',
    'دعم العملاء',
    'سجل التدقيق',
    'طلبات الخدمة',
    'أكواد الخصم',
    'طلبات تسجيل جملة',
    'تجار الجملة',
    'المراجعات',
    'التقارير والتحليلات',
    'إعدادات البريد',
    'العروض',
    'المناقصات',
    'عمولات المناقصات',
    'بنرات المدونة',
    'الأقسام الفرعية',
    'الأقسام الرئيسية',
    'المتاجر المميزة',
    'Boost المنتجات',
    'إعدادات العمولة العامة',
    'أنواع المتاجر',
    'الأجهزة والجلسات',
    'إدارة التوصيل',
    'طلبات السائقين',
  ];

  Widget _body() {
    switch (_index) {
      case 0:
        return const AdminOverviewScreen();
      case 1:
        return const AdminMigrationHubSection();
      case 2:
        return const AdminUsersScreen();
      case 3:
        return const AdminCategoriesSection();
      case 4:
        return const AdminTechSpecialtiesSection();
      case 5:
        return const AdminBannerManagerSection();
      case 6:
        return const AdminProductsScreen(initialTab: AdminProductsTabIndex.products);
      case 7:
        return const AdminOrdersSection();
      case 36:
        return const AdminDeliveryDashboardPage();
      case 37:
        return const AdminDriverRequestsPage();
      case 8:
        return const AdminTechniciansSection();
      case 9:
        return const AdminStoresScreen(initialTab: AdminStoresTabIndex.storeRequests);
      case 10:
        return const AdminHomeToolsStoresSection();
      case 11:
        return const AdminReportsSection();
      case 12:
        return const AdminCommissionsSection();
      case 13:
        return const AdminWalletSection();
      case 14:
        return const AdminSettingsScreen();
      case 15:
        return const AdminStoreCategoriesSection();
      case 16:
        return const AdminSupportChatsSection();
      case 17:
        return const AdminAuditLogScreen();
      case 18:
        return const AdminServiceRequestsSection();
      case 19:
      case 25:
        return const AdminPromotionsScreen();
      case 20:
        return const AdminWholesaleManagementSection(initialTab: 0);
      case 21:
        return const AdminWholesaleManagementSection(initialTab: 1);
      case 22:
        return const AdminReviewsSection();
      case 23:
        return const AdminAnalyticsSection();
      case 26:
        return const AdminTendersSection();
      case 27:
        return const AdminTenderCommissionsSection();
      case 28:
        return const AdminBlogBannersSection();
      // تطابق عناوين القائمة مع تبويبات AdminStoresScreen (انظر AdminStoresTabIndex).
      case 29:
        return const AdminStoresScreen(initialTab: AdminStoresTabIndex.subCategories);
      case 30:
        return const AdminStoresScreen(initialTab: AdminStoresTabIndex.homeSections);
      case 31:
        return const AdminStoresScreen(initialTab: AdminStoresTabIndex.featuredStores);
      case 32:
        return const AdminProductsScreen(initialTab: AdminProductsTabIndex.productBoost);
      case 33:
        return const AdminSettingsScreen();
      case 34:
        return const AdminStoresScreen(initialTab: AdminStoresTabIndex.storeTypes);
      case 35:
        return const AdminSessionsSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGroupedNav(
    List<_AdminNavGroup> groups, {
    VoidCallback? onItemSelected,
  }) {
    return Material(
      color: AppColors.navy,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.white24,
          splashColor: Colors.white10,
          highlightColor: Colors.white10,
        ),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                'لوحة الإدارة',
                style: GoogleFonts.tajawal(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
            for (final g in groups)
              ExpansionTile(
                initiallyExpanded: true,
                maintainState: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                collapsedShape: const RoundedRectangleBorder(),
                shape: const RoundedRectangleBorder(),
                iconColor: Colors.white70,
                collapsedIconColor: Colors.white70,
                title: Text(
                  g.titleAr,
                  style: GoogleFonts.tajawal(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.right,
                ),
                children: [
                  for (final e in g.items)
                    ListTile(
                      dense: true,
                      selected: _index == e.index,
                      selectedTileColor: Colors.white12,
                      leading: Icon(
                        e.icon,
                        size: 22,
                        color: _index == e.index
                            ? AppColors.orange
                            : Colors.white70,
                      ),
                      title: Text(
                        e.labelAr,
                        style: GoogleFonts.tajawal(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: _index == e.index
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      onTap: () {
                        setState(() => _index = e.index);
                        onItemSelected?.call();
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _notificationBell({
    required Color iconColor,
    required String adminRole,
  }) {
    return _AdminNotificationBell(
      iconColor: iconColor,
      adminRole: adminRole,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BackendIdentityController.instance,
      builder: (context, _) {
        final authUid = UserSession.currentUid;
        final me = BackendIdentityController.instance.me;
        final data = me == null
            ? null
            : <String, dynamic>{
                'role': me.role,
                'email': me.email,
              };
        if (!_canAccessAdminDashboard(data, authUid)) {
              return Scaffold(
                backgroundColor: AppColors.background,
                appBar: AppBar(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  leading: const AppBarBackButton(),
                  title: Text(
                    'لوحة الإدارة',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                  ),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'غير مصرح بالوصول إلى لوحة الإدارة.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              );
            }

            final role = BackendIdentityController.instance.me?.role ?? PermissionService.roleAdmin;
            final navGroups = _filteredNavGroups(role);

            _maybeScheduleNavSync(
              uid: authUid,
              userData: data,
              role: role,
            );

            final wide = MediaQuery.sizeOf(context).width >= 760;

            if (wide) {
              return Scaffold(
                backgroundColor: AppColors.background,
                body: Row(
                  children: [
                    SizedBox(width: 292, child: _buildGroupedNav(navGroups)),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            color: Colors.white,
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  const AppBarBackButton(),
                                  _notificationBell(
                                    iconColor: AppColors.navy,
                                    adminRole: role,
                                  ),
                                  Expanded(
                                    child: Text(
                                      _titles[_index],
                                      style: GoogleFonts.tajawal(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(child: _body()),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                centerTitle: true,
                leading: const AppBarBackButton(),
                actions: [
                  _notificationBell(iconColor: Colors.white, adminRole: role),
                ],
                title: Text(
                  _titles[_index],
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w800),
                ),
              ),
              drawer: Drawer(
                child: SafeArea(
                  child: _buildGroupedNav(
                    navGroups,
                    onItemSelected: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              body: _body(),
            );
      },
    );
  }
}

class _AdminNotificationBell extends StatefulWidget {
  const _AdminNotificationBell({
    required this.iconColor,
    required this.adminRole,
  });

  final Color iconColor;
  final String adminRole;

  @override
  State<_AdminNotificationBell> createState() => _AdminNotificationBellState();
}

class _AdminNotificationBellState extends State<_AdminNotificationBell> {
  Timer? _timer;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = await AdminNotificationRepository.fetchUnreadCount();
    if (!mounted) return;
    setState(() {
      _unread = switch (state) {
        FeatureSuccess(:final data) => data,
        _ => 0,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'إشعارات الإدارة',
          icon: Icon(Icons.notifications_outlined, color: widget.iconColor),
          onPressed: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AdminNotificationsScreen(adminRole: widget.adminRole),
              ),
            );
            await _refresh();
          },
        ),
        if (_unread > 0)
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
              child: Text(
                _unread > 99 ? '99+' : '$_unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
