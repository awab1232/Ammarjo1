import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/config/backend_orders_config.dart';
import '../../../../core/contracts/feature_state.dart';
import '../../../../core/data/repositories/product_repository.dart';
import '../../../../core/network/network_errors.dart';
import '../../../../core/services/backend_orders_client.dart';
import '../../../coupons/data/coupon_repository.dart';
import '../../../coupons/domain/coupon_model.dart';
import '../../../promotions/data/promotion_repository.dart';
import '../../../promotions/domain/promotion_model.dart';
import '../../data/local_storage_service.dart';
import '../../domain/models.dart';

/// سلة التسوق والمخزون المحلي.
class CartController extends ChangeNotifier {
  CartController(this._local);

  final LocalStorageService _local;

  List<CartItem> cart = <CartItem>[];
  String? errorMessage;
  Coupon? appliedCoupon;
  double discountAmount = 0;
  List<Promotion> appliedPromotions = <Promotion>[];
  double promotionsDiscountAmount = 0;
  bool freeShippingByPromotion = false;

  double get cartTotal => cart.fold(0, (total, item) => total + item.totalPrice);
  double get cartTotalAfterDiscount {
    final v = cartTotal - discountAmount;
    return v < 0 ? 0 : v;
  }
  int get cartItemCount => cart.fold(0, (total, item) => total + item.quantity);

  bool get _useServerCartLines {
    final u = FirebaseAuth.instance.currentUser;
    return BackendOrdersConfig.useBackendCart &&
        u != null &&
        BackendOrdersConfig.baseUrl.trim().isNotEmpty;
  }

  Future<void> _saveLocalSpecialLinesOnly() async {
    final special = cart.where((e) => e.isTender || e.isWholesale).toList();
    await _local.saveCart(special);
  }

  Future<void> loadPersistedCart() async {
    List<CartItem> localRaw;
    try {
      localRaw = await _local.getCart();
    } on StateError {
      // مفتاح السلة غير موجود أو فارغ — لا نرمي أثناء bootstrap
      localRaw = <CartItem>[];
    }
    final localSpecial = localRaw.where((e) => e.isTender || e.isWholesale).toList();
    if (_useServerCartLines) {
      final rows = await BackendOrdersClient.instance.fetchCart();
      final server = rows == null
          ? <CartItem>[]
          : rows.map(CartItem.fromBackendCartRow).toList();
      cart = <CartItem>[...server, ...localSpecial];
      await _local.saveCart(localSpecial);
      notifyListeners();
      return;
    }
    cart = List<CartItem>.from(localRaw);
    notifyListeners();
  }

  void _clearDiscounts() {
    if (appliedCoupon != null) {
      appliedCoupon = null;
      discountAmount = 0;
    }
    appliedPromotions = <Promotion>[];
    promotionsDiscountAmount = 0;
    freeShippingByPromotion = false;
  }

  Future<void> addToCart(
    Product product, {
    String storeId = 'ammarjo',
    String storeName = 'متجر عمّار جو',
    ProductVariant? selectedVariant,
  }) async {
    if (product.hasVariants && selectedVariant == null) {
      errorMessage = 'يرجى اختيار متغير المنتج أولاً.';
      notifyListeners();
      return;
    }
    if (!product.isAvailableForPurchase) {
      errorMessage = 'هذا المنتج غير متوفر حالياً.';
      notifyListeners();
      return;
    }

    if (_useServerCartLines && product.id > 0) {
      final price = (selectedVariant?.price ?? product.price).trim();
      final img = product.images.isNotEmpty ? product.images.first : '';
      final ok = await BackendOrdersClient.instance.postCartItem(
        productId: product.id,
        variantId: selectedVariant?.id,
        quantity: 1,
        priceSnapshot: price,
        productName: product.name,
        imageUrl: img,
        storeId: storeId,
        storeName: storeName,
      );
      if (!ok) {
        errorMessage = 'تعذّر تحديث السلة.';
      } else {
        errorMessage = null;
        _clearDiscounts();
        await loadPersistedCart();
      }
      notifyListeners();
      return;
    }

    final index = cart.indexWhere(
      (item) =>
          item.product.id == product.id &&
          item.storeId == storeId &&
          (item.selectedVariant?.id ?? '') == (selectedVariant?.id ?? ''),
    );
    if (index >= 0) {
      cart[index].quantity += 1;
    } else {
      cart.add(
        CartItem(
          product: product,
          quantity: 1,
          storeId: storeId,
          storeName: storeName,
          selectedVariant: selectedVariant,
        ),
      );
    }
    await _local.saveCart(cart);
    _clearDiscounts();
    errorMessage = null;
    notifyListeners();
  }

  Future<void> addCartItem(CartItem item) async {
    if (_useServerCartLines && item.product.id > 0 && !item.isTender && !item.isWholesale) {
      final price = (item.selectedVariant?.price ?? item.product.price).trim();
      final ok = await BackendOrdersClient.instance.postCartItem(
        productId: item.product.id,
        variantId: item.selectedVariant?.id,
        quantity: item.quantity,
        priceSnapshot: price,
        productName: item.product.name,
        imageUrl: item.imageUrl,
        storeId: item.storeId,
        storeName: item.storeName,
      );
      if (!ok) {
        errorMessage = 'تعذّر تحديث السلة.';
      } else {
        errorMessage = null;
        _clearDiscounts();
        await loadPersistedCart();
      }
      notifyListeners();
      return;
    }

    cart.add(item);
    await _local.saveCart(cart);
    _clearDiscounts();
    errorMessage = null;
    notifyListeners();
  }

  Future<void> updateQuantity(int productId, int quantity, {String storeId = 'ammarjo'}) async {
    if (quantity <= 0) {
      await removeFromCart(productId, storeId: storeId);
      return;
    }
    final index = cart.indexWhere(
      (item) => item.product.id == productId && item.storeId == storeId,
    );
    if (index == -1) return;

    final line = cart[index];
    if (_useServerCartLines &&
        line.backendLineId != null &&
        line.backendLineId!.isNotEmpty &&
        line.product.id > 0) {
      final ok = await BackendOrdersClient.instance.patchCartItemQuantity(
        lineId: line.backendLineId!,
        quantity: quantity,
      );
      if (!ok) {
        errorMessage = 'تعذّر تحديث السلة.';
        notifyListeners();
        return;
      }
      _clearDiscounts();
      await loadPersistedCart();
      notifyListeners();
      return;
    }

    cart[index].quantity = quantity;
    await _local.saveCart(cart);
    _clearDiscounts();
    notifyListeners();
  }

  Future<void> increaseCartLineQty(CartItem item) async {
    await updateQuantity(item.product.id, item.quantity + 1, storeId: item.storeId);
  }

  Future<void> decreaseCartLineQty(CartItem item) async {
    await updateQuantity(item.product.id, item.quantity - 1, storeId: item.storeId);
  }

  Future<void> removeFromCart(int productId, {String storeId = 'ammarjo'}) async {
    final index = cart.indexWhere(
      (item) => item.product.id == productId && item.storeId == storeId,
    );
    if (index < 0) return;
    final line = cart[index];

    if (_useServerCartLines &&
        line.backendLineId != null &&
        line.backendLineId!.isNotEmpty &&
        line.product.id > 0) {
      final ok = await BackendOrdersClient.instance.deleteCartItem(line.backendLineId!);
      if (!ok) {
        errorMessage = 'تعذّر تحديث السلة.';
        notifyListeners();
        return;
      }
      _clearDiscounts();
      await loadPersistedCart();
      notifyListeners();
      return;
    }

    cart.removeWhere(
      (item) => item.product.id == productId && item.storeId == storeId,
    );
    await _local.saveCart(cart);
    _clearDiscounts();
    notifyListeners();
  }

  Future<void> removeCartLine(CartItem item) async {
    await removeFromCart(item.product.id, storeId: item.storeId);
  }

  Future<void> clearCart() async {
    if (_useServerCartLines) {
      await BackendOrdersClient.instance.deleteCartClear();
      cart = cart.where((e) => e.isTender || e.isWholesale).toList();
      await _saveLocalSpecialLinesOnly();
      appliedCoupon = null;
      discountAmount = 0;
      appliedPromotions = <Promotion>[];
      promotionsDiscountAmount = 0;
      freeShippingByPromotion = false;
      notifyListeners();
      return;
    }

    cart = <CartItem>[];
    await _local.saveCart(cart);
    appliedCoupon = null;
    discountAmount = 0;
    appliedPromotions = <Promotion>[];
    promotionsDiscountAmount = 0;
    freeShippingByPromotion = false;
    notifyListeners();
  }

  /// [lines] إن وُجدت يُحسب الكوبون على هذه الأسطر فقط (مثلاً متجر واحد من السلة).
  Future<bool> applyCoupon(String code, String userId, {List<CartItem>? lines}) async {
    final scope = lines ?? cart;
    try {
      final state = await CouponRepository.instance.validateCoupon(code, userId, scope);
      if (state is! FeatureSuccess<CouponValidationResult>) {
        errorMessage = state is FeatureFailure<CouponValidationResult>
            ? state.message
            : 'تعذّر تطبيق الكوبون.';
        notifyListeners();
        return false;
      }
      final res = state.data;
      appliedCoupon = res.coupon;
      discountAmount = res.discountAmount;
      errorMessage = null;
      notifyListeners();
      return true;
    } on Object {
      errorMessage = networkUserMessage('unexpected error').isNotEmpty ? networkUserMessage('unexpected error') : 'unexpected error';
      notifyListeners();
      return false;
    }
  }

  void removeCoupon() {
    appliedCoupon = null;
    discountAmount = 0;
    notifyListeners();
  }

  /// [lines] إن وُجدت تُحسب العروض على هذه الأسطر فقط.
  Future<bool> applyPromotions(String userId, {List<CartItem>? lines}) async {
    final scope = lines ?? cart;
    try {
      final state = await PromotionRepository.instance.calculateDiscount(scope, userId);
      if (state is! FeatureSuccess<PromotionsCalculationResult>) {
        errorMessage = state is FeatureFailure<PromotionsCalculationResult>
            ? state.message
            : 'تعذّر حساب العروض.';
        notifyListeners();
        return false;
      }
      final res = state.data;
      if (appliedCoupon != null && res.appliedPromotions.any((e) => !e.isStackable)) {
        errorMessage = 'لا يمكن دمج عرض غير قابل للدمج مع كوبون.';
        notifyListeners();
        return false;
      }
      appliedPromotions = res.appliedPromotions;
      promotionsDiscountAmount = res.discountAmount;
      freeShippingByPromotion = res.freeShipping;
      errorMessage = null;
      notifyListeners();
      return true;
    } on Object {
      errorMessage = networkUserMessage('unexpected error').isNotEmpty ? networkUserMessage('unexpected error') : 'unexpected error';
      notifyListeners();
      return false;
    }
  }

  void clearPromotions() {
    appliedPromotions = <Promotion>[];
    promotionsDiscountAmount = 0;
    freeShippingByPromotion = false;
    notifyListeners();
  }

  /// خصومات الكوبون/العروض المرتبطة بـ [lines] فقط (لطلب متجر واحد أو أي مجموعة أسطر).
  Future<
      ({
        double couponDiscount,
        double promotionsDiscount,
        bool freeShipping,
        List<String> promotionIds,
      })> checkoutDiscountBreakdownForLines(List<CartItem> lines, String userId) async {
    if (lines.isEmpty) {
      return (
        couponDiscount: 0.0,
        promotionsDiscount: 0.0,
        freeShipping: false,
        promotionIds: <String>[],
      );
    }
    double couponDiscount = 0;
    final c = appliedCoupon;
    if (c != null) {
      final orderAmount = lines.fold<double>(0, (s, e) => s + e.totalPrice);
      final productIds = lines.map((e) => e.product.id).toList();
      final storeIds = lines.map((e) => e.storeId).toSet().toList();
      if (c.isValid(
        userId: userId,
        orderAmount: orderAmount,
        productIds: productIds,
        storeIds: storeIds,
        userUsedCount: 0,
      )) {
        couponDiscount = c.calculateDiscount(orderAmount: orderAmount);
      }
    }

    final promoState = await PromotionRepository.instance.calculateDiscount(lines, userId);
    if (promoState is! FeatureSuccess<PromotionsCalculationResult>) {
      return (
        couponDiscount: couponDiscount,
        promotionsDiscount: 0.0,
        freeShipping: false,
        promotionIds: <String>[],
      );
    }
    final res = promoState.data;
    if (c != null && couponDiscount > 0 && res.appliedPromotions.any((e) => !e.isStackable)) {
      return (
        couponDiscount: couponDiscount,
        promotionsDiscount: 0.0,
        freeShipping: false,
        promotionIds: <String>[],
      );
    }
    return (
      couponDiscount: couponDiscount,
      promotionsDiscount: res.discountAmount,
      freeShipping: res.freeShipping,
      promotionIds: res.appliedPromotions.map((e) => e.id).toList(),
    );
  }

  Future<void> refreshCartFromCatalog() async {
    if (cart.isEmpty || !Firebase.apps.isNotEmpty) return;
    try {
      if (_useServerCartLines) {
        await loadPersistedCart();
        return;
      }
      final next = <CartItem>[];
      for (final item in cart) {
        if (item.isTender) {
          next.add(item);
          continue;
        }
        final state = await BackendProductRepository.instance.fetchProductByWooId(item.product.id);
        switch (state) {
          case FeatureSuccess(:final data):
            final fresh = data;
            if (fresh != null) {
              final img = fresh.images.isNotEmpty ? fresh.images.first : item.imageUrl;
              next.add(
                CartItem(
                  product: fresh,
                  quantity: item.quantity,
                  backendLineId: item.backendLineId,
                  storeId: item.storeId,
                  storeName: item.storeName,
                  imageUrl: img.isNotEmpty ? img : CartItem.defaultImageUrlForProduct(fresh),
                  selectedVariant: item.selectedVariant,
                ),
              );
            } else {
              next.add(item);
            }
          case FeatureMissingBackend():
          case FeatureAdminNotWired():
          case FeatureAdminMissingEndpoint():
          case FeatureCriticalPublicDataFailure():
          case FeatureFailure():
            errorMessage = errorMessage ?? 'تعذّر تحديث السلة من الخادم.';
            next.add(item);
        }
      }
      cart = next;
      await _local.saveCart(cart);
      notifyListeners();
    } on Object {
      final net = networkUserMessage('unexpected error');
      if (net.isNotEmpty) {
        errorMessage = net;
        notifyListeners();
      }
    }
  }
}
