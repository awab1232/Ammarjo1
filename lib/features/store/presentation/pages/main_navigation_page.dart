import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/firebase/chat_firebase_sync.dart';
import '../../../../core/firebase/local_chat_notification_service.dart';
import '../../../../core/widgets/keep_alive_tab.dart';
import '../../../../core/widgets/ai_assistant_fab.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../maintenance/presentation/pages/maintenance_page.dart';
import '../../../maintenance/presentation/pages/technician_dashboard_page.dart';
import '../../../stores/presentation/stores_home_page.dart';
import '../controllers/cart_controller.dart';
import '../store_controller.dart';
import '../widgets/app_drawer.dart';
import 'ai_assistant_page.dart';
import 'cart_page.dart';
import 'login_page.dart';
import 'my_orders_page.dart';
import 'profile_page.dart';
import 'smart_quantity_calculator_page.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _index = 0;
  final GlobalKey<ScaffoldState> _shellKey = GlobalKey<ScaffoldState>();
  late final StoreController _store;

  int _mapPendingTabForShell(int logical) {
    if (!kIsWeb) {
      switch (logical) {
        case 0:
          return 0;
        case 1:
          return 1;
        case 4:
          return 2;
        case 5:
          return 3;
        default:
          return logical.clamp(0, 3);
      }
    }
    switch (logical) {
      case 0:
        return 0;
      case 1:
        return 1;
      case 4:
        return 2;
      case 5:
        return 3;
      default:
        return logical.clamp(0, 3);
    }
  }

  void _applyPendingTabFromStore() {
    final idx = _store.takePendingMainNavigationIndex();
    if (idx != null && mounted) {
      setState(() => _index = _mapPendingTabForShell(idx));
    }
  }

  void _onStoreForMainNav() => _applyPendingTabFromStore();

  @override
  void initState() {
    super.initState();
    _store = context.read<StoreController>();
    _store.addListener(_onStoreForMainNav);
    _store.onBannedByAdmin = _handleBannedByAdmin;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyPendingTabFromStore();
      syncChatFirebaseIdentity(_store.profile);
    });
  }

  /// حظر فوري: حوار ثم تسجيل خروج وشاشة الدخول (يُستدعى من [StoreController] بدون استيراد واجهة هناك).
  Future<void> _handleBannedByAdmin() async {
    final navCtx = appNavigatorKey.currentContext;
    if (navCtx == null) return;
    await showDialog<void>(
      context: navCtx,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('تنبيه', style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        content: Text(
          'تم حظر حسابك من قبل الإدارة',
          textAlign: TextAlign.right,
          style: GoogleFonts.tajawal(height: 1.35),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('حسناً', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
    await _store.logout();
    // بعد تسجيل الخروج ننتظر إطاراً لتفادي استخدام سياق عبر فجوة async.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (route) => false,
      );
    });
  }

  @override
  void dispose() {
    _store.onBannedByAdmin = null;
    _store.removeListener(_onStoreForMainNav);
    super.dispose();
  }

  void _openDrawer() => _shellKey.currentState?.openDrawer();

  void _openTechnicianDashboard() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const TechnicianDashboardPage()),
    );
  }

  void _goToMaintenance() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MaintenancePage(
          onOpenDrawer: _openDrawer,
          onOpenTechnicianDashboard: _openTechnicianDashboard,
        ),
      ),
    );
  }

  void _openAiAssistant() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AiAssistantPage(
          onBookMaintenance: _goToMaintenance,
          onOpenQuantityCalculator: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SmartQuantityCalculatorPage()),
            );
          },
        ),
      ),
    );
  }

  /// 0 الرئيسية (الصفحة المعاد تصميمها: متاجر + أقسام + شارات).
  /// 1 طلباتي. 2 السلة. 3 حسابي.
  late final List<Widget> _pages = [
    KeepAliveTab(
      child: StoresHomePage(
        onOpenDrawer: _openDrawer,
        appBarTitle: 'الرئيسية',
      ),
    ),
    const KeepAliveTab(child: MyOrdersPage()),
    const KeepAliveTab(child: CartPage()),
    const KeepAliveTab(child: ProfilePage()),
  ];

  int get _shellIndexMax => _pages.length - 1;

  List<BottomNavigationBarItem> _bottomNavItems(int cartCount) {
    final unread = LocalChatNotificationService.unreadBadgeCount.value;
    return [
      const BottomNavigationBarItem(
        icon: Icon(Icons.home_rounded),
        label: 'الرئيسية',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'طلباتي',
      ),
      BottomNavigationBarItem(
        icon: Badge(
          isLabelVisible: cartCount > 0,
          label: Text('$cartCount'),
          child: const Icon(Icons.shopping_cart_outlined),
        ),
        label: 'السلة',
      ),
      BottomNavigationBarItem(
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: const Icon(Icons.person_outline),
        ),
        label: 'حسابي',
      ),
    ];
  }

  /// شريط سفلي ثابت للويب: رفيع، حد علوي برتقالي، بدون تضخيم Material الافتراضي.
  Widget _webBottomNavigationBar(int cartCount) {
    return Material(
      elevation: 10,
      shadowColor: const Color(0x33000000),
      color: Colors.white,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: AppColors.primaryOrange.withValues(alpha: 0.28), width: 2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 2),
          child: SizedBox(
            height: 54,
            child: Theme(
              data: Theme.of(context).copyWith(
                splashColor: AppColors.primaryOrange.withValues(alpha: 0.12),
                highlightColor: AppColors.primaryOrange.withValues(alpha: 0.06),
              ),
              child: BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _index.clamp(0, _shellIndexMax),
                onTap: (i) => setState(() => _index = i.clamp(0, _shellIndexMax)),
                selectedItemColor: const Color(0xFFFF6B00),
                unselectedItemColor: Colors.grey.shade600,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedFontSize: 10,
                unselectedFontSize: 9,
                iconSize: 22,
                items: _bottomNavItems(cartCount),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.watch<CartController>().cart.length;

    final safeIndex = _index.clamp(0, _shellIndexMax);
    if (_index > _shellIndexMax) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_index > _shellIndexMax) {
          setState(() => _index = _shellIndexMax);
        }
      });
    }
    final content = IndexedStack(
      index: safeIndex,
      children: _pages,
    );

    return Scaffold(
      key: _shellKey,
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      extendBody: false,
      drawer: const AppDrawer(),
      body: content,
      floatingActionButton: AiAssistantFab(
        onPressed: _openAiAssistant,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: ListenableBuilder(
        listenable: LocalChatNotificationService.unreadBadgeCount,
        builder: (context, _) => kIsWeb
            ? _webBottomNavigationBar(cartCount)
            : BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: safeIndex,
                onTap: (i) => setState(() => _index = i.clamp(0, _shellIndexMax)),
                selectedItemColor: const Color(0xFFFF6B00),
                unselectedItemColor: Colors.grey,
                backgroundColor: Colors.white,
                elevation: 8,
                items: _bottomNavItems(cartCount),
              ),
      ),
    );
  }
}
