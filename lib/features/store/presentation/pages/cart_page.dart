import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bar_back_button.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/empty_state_widget.dart';
import '../../../../core/utils/web_image_url.dart';
import '../../../../core/widgets/ammar_cached_image.dart';
import '../../domain/models.dart';
import '../store_controller.dart';
import 'checkout_page.dart';
import 'login_page.dart';

/// تجميع أسطر السلة حسب [CartItem.storeId] لعرض متعدد المتاجر.
List<MapEntry<String, List<CartItem>>> _groupCartByStore(List<CartItem> cart) {
  final map = <String, List<CartItem>>{};
  for (final item in cart) {
    final id = item.storeId;
    map[id] = [...(map[id] ?? <CartItem>[]), item];
  }
  final keys = map.keys.toList()
    ..sort((a, b) {
      if (a == 'ammarjo') return -1;
      if (b == 'ammarjo') return 1;
      return a.compareTo(b);
    });
  return keys.map((k) => MapEntry(k, map[k]!)).toList();
}

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCartWithServer());
  }

  Future<void> _syncCartWithServer() async {
    final store = context.read<StoreController>();
    if (store.cart.isEmpty) return;
    setState(() => _syncing = true);
    try {
      await store.refreshCartFromCatalog();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _placeOrderForStore(
    BuildContext context,
    StoreController store,
    List<CartItem> items,
  ) async {
    if (items.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يجب تسجيل الدخول أو إنشاء حساب لإتمام الطلب',
            style: GoogleFonts.tajawal(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CheckoutPage(checkoutLines: List<CartItem>.from(items)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.tajawalTextTheme(Theme.of(context).textTheme);

    return Consumer<StoreController>(
      builder: (context, store, _) {
        final grouped = _groupCartByStore(store.cart);

        return Theme(
          data: Theme.of(context).copyWith(textTheme: textTheme),
          child: PopScope(
            // تأكيد المغادرة عند وجود عناصر — لتفادي فقدان السلة دون قصد.
            canPop: store.cart.isEmpty,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) return;
              final leave = await AppBottomSheet.confirm(
                context: context,
                title: 'مغادرة السلة؟',
                message: 'هل تريد المغادرة؟ سلتك غير فارغة.',
                confirmLabel: 'مغادرة',
                cancelLabel: 'البقاء',
              );
              if (leave == true && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              centerTitle: true,
              leading: const AppBarBackButton(),
              title: Text(
                'السلة',
                style: GoogleFonts.tajawal(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              bottom: _syncing
                  ? const PreferredSize(
                      preferredSize: Size.fromHeight(3),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: AppColors.orange,
                        backgroundColor: AppColors.orangeLight,
                      ),
                    )
                  : null,
            ),
            body: store.cart.isEmpty
                ? EmptyStateWidget(
                    type: EmptyStateType.cart,
                    onAction: () {
                      // «تسوّق الآن» → تبويب «الرئيسية» (الفهرس المنطقي 0) عبر الـ shell.
                      store.requestNavigateToMainTab(0);
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = kIsWeb && constraints.maxWidth >= 1100;
                      final cartList = ListView(
                          padding: const EdgeInsets.only(bottom: 8),
                          children: grouped.map((entry) {
                            final items = entry.value;
                            final storeName = items.first.storeName.isNotEmpty
                                ? items.first.storeName
                                : 'متجر عمار جو';
                            final storeTotal = items.fold<double>(0, (sum, i) => sum + i.totalPrice);

                            return Card(
                              margin: const EdgeInsets.all(12),
                              elevation: 2,
                              shadowColor: AppColors.shadow,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryOrange.withValues(alpha: 0.1),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(16),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.store, color: AppColors.primaryOrange),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            storeName,
                                            style: GoogleFonts.tajawal(
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primaryOrange,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...items.map(
                                    (item) => _CartStoreLineTile(
                                      item: item,
                                      store: store,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: FutureBuilder<StoreShippingComputation>(
                                      future: store.computeShippingForCartLines(items),
                                      builder: (context, snap) {
                                        final fee = snap.data?.totalShipping ?? 0.0;
                                        final totalWithShipping = storeTotal + fee;
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'المجموع: ${store.formatMoney(storeTotal)} ${store.currency.code}',
                                                  style: GoogleFonts.tajawal(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    color: AppColors.textPrimary,
                                                  ),
                                                ),
                                                Text(
                                                  fee <= 0
                                                      ? 'الشحن: مجاني'
                                                      : 'الشحن: ${store.formatMoney(fee)}',
                                                  style: GoogleFonts.tajawal(fontSize: 12, color: AppColors.textSecondary),
                                                ),
                                                Text(
                                                  'الإجمالي: ${store.formatMoney(totalWithShipping)}',
                                                  style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.w700),
                                                ),
                                              ],
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.primaryOrange,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                              onPressed: () => _placeOrderForStore(context, store, items),
                                              child: Text(
                                                'اطلب من هذا المتجر',
                                                style: GoogleFonts.tajawal(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      if (isDesktop) {
                        return Row(
                          children: [
                            Expanded(child: cartList),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: 360,
                              child: _CartGrandTotalBar(store: store),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(child: cartList),
                          _CartGrandTotalBar(store: store),
                        ],
                      );
                    },
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _CartStoreLineTile extends StatelessWidget {
  const _CartStoreLineTile({
    required this.item,
    required this.store,
  });

  final CartItem item;
  final StoreController store;

  @override
  Widget build(BuildContext context) {
    final url = (item.isTender ? (item.tenderImageUrl ?? item.imageUrl) : item.imageUrl).trim().isNotEmpty
        ? webSafeImageUrl(item.isTender ? (item.tenderImageUrl ?? item.imageUrl) : item.imageUrl)
        : webSafeFirstProductImage(item.product.images);

    return Material(
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 50,
            height: 50,
            child: url.isEmpty
                ? ColoredBox(
                    color: AppColors.orangeLight,
                    child: Icon(Icons.image_outlined, color: AppColors.orange.withValues(alpha: 0.5)),
                  )
                : AmmarCachedImage(
                    imageUrl: url,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    productTileStyle: true,
                  ),
          ),
        ),
        title: Row(
          children: [
            if (item.isTender)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('مناقصة', style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primaryOrange)),
              ),
            Expanded(
              child: Text(
                item.isTender ? item.product.name : item.product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${store.formatPrice(item.product.price)} دينار',
          textAlign: TextAlign.right,
          style: GoogleFonts.tajawal(fontSize: 13, color: AppColors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.primaryOrange),
              onPressed: () => store.decreaseCartLineQty(item),
            ),
            Text(
              '${item.quantity}',
              style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryOrange),
              onPressed: () => store.increaseCartLineQty(item),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary),
              onPressed: () => store.removeCartLine(item),
              tooltip: 'حذف',
            ),
          ],
        ),
      ),
    );
  }
}

class _CartGrandTotalBar extends StatelessWidget {
  const _CartGrandTotalBar({required this.store});

  final StoreController store;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoreShippingComputation>(
      future: store.computeShippingForCartLines(store.cart),
      builder: (context, snap) {
        final shipping = snap.data?.totalShipping ?? 0.0;
        final total = store.cartSubtotal + shipping;
        return Material(
          elevation: 12,
          shadowColor: AppColors.shadow,
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'إجمالي السلة',
                        style: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      Text(
                        store.formatMoney(total),
                        style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shipping <= 0 ? 'الشحن مجاني' : 'إجمالي الشحن: ${store.formatMoney(shipping)}',
                    style: GoogleFonts.tajawal(fontSize: 11, color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
