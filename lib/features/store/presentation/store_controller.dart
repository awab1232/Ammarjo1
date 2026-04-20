import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../../../core/data/repositories/order_repository.dart';
import '../../../core/data/repositories/store_repository.dart';
import '../../../core/firebase/account_password_service.dart';
import '../../../core/firebase/chat_firebase_sync.dart';
import '../../../core/firebase/phone_auth_service.dart';
import '../../../core/firebase/users_repository.dart';
import '../../../core/services/phone_password_auth_service.dart';
import '../../../core/constants/jordan_regions.dart';
import '../../../core/utils/jordan_phone.dart';
import '../../../core/utils/web_image_url.dart';
import '../../../core/config/shipping_policy.dart';
import '../../../core/contracts/feature_state.dart';
import '../domain/catalog_active_filters.dart';
import '../data/local_storage_service.dart';
// import '../data/woo_api_service.dart'; // LEGACY - WooCommerce REST
import '../domain/favorite_product.dart';
import '../domain/models.dart';
import '../domain/product_derived_categories.dart';
import '../domain/saved_checkout_info.dart';
import '../domain/store_currency.dart';
import '../domain/wp_home_banner.dart';
import '../../coupons/domain/coupon_model.dart';
import '../../promotions/domain/promotion_model.dart';
import '../../stores/domain/shipping_policy.dart' as store_shipping;
import 'controllers/cart_controller.dart';
import 'controllers/catalog_controller.dart';
import 'controllers/filter_controller.dart';
import 'controllers/search_controller.dart';
import 'controllers/user_controller.dart';

/// واجهة موحّدة للمتجر — تفويض إلى متحكمات متخصصة.
/// يُفضّل استخدام [CatalogController] و [SearchController] وغيرها مباشرة من [Provider].
@Deprecated('يُفضّل استخدام CatalogController / SearchController / FilterController / CartController / UserController من السياق')
class StoreController extends ChangeNotifier {
  // LEGACY - WooCommerce REST (Migration Hub uses WooApiService directly.)
  // final WooApiService _api = WooApiService();
  final LocalStorageService _local = LocalStorageService();

  StreamSubscription<FeatureState<List<FavoriteProduct>>>? _favoritesSub;

  StoreController() {
    catalog = CatalogController();
    search = SearchController();
    filter = FilterController();
    cartState = CartController(_local);
    user = UserController(_local);
    search.onBeforeSearchClearFilters = () => filter.clearFiltersSilently();
    filter.onBeforeApplyClearSearch = () => search.clearSearchSilently();
    void forward() => notifyListeners();
    catalog.addListener(forward);
    search.addListener(forward);
    filter.addListener(forward);
    cartState.addListener(forward);
    user.addListener(forward);
  }

  /// كتالوج المنتجات والأقسام.
  late final CatalogController catalog;

  /// بحث خادمي.
  late final SearchController search;

  /// تصفية خادمية.
  late final FilterController filter;

  /// سلة التسوق.
  late final CartController cartState;

  /// الملف والحظر.
  late final UserController user;

  /// يُسجَّل من [MainNavigationPage] لعرض حوار الحظر والتنقل دون استيراد دوال UI هنا (تجنّب دورات الاستيراد).
  Future<void> Function()? get onBannedByAdmin => user.onBannedByAdmin;
  set onBannedByAdmin(Future<void> Function()? v) => user.onBannedByAdmin = v;

  bool get catalogHasMore => catalog.catalogHasMore;
  bool get isLoadingMoreProducts => catalog.isLoadingMoreProducts;

  /// يُملأ بعد [sendPhoneVerificationCode] لإكمال [verifyPhoneCode].
  String? phoneVerificationId;
  int? phoneResendToken;

  /// بعد [loginWithLocalBypass]: تبويب الرئيسية في [MainNavigationPage] (0).
  int? _pendingMainNavigationIndex;

  /// يُستدعى من الصدفة الرئيسية عند كل [notifyListeners]؛ يُفرغ الانتظار مرة واحدة.
  int? takePendingMainNavigationIndex() {
    final v = _pendingMainNavigationIndex;
    _pendingMainNavigationIndex = null;
    return v;
  }

  /// طلب تبديل تبويب الشريط السفلي من أي مكان في التطبيق (مثل زر «تسوّق الآن» في السلة).
  /// الفهرس المنطقي: 0 = الرئيسية، 1 = طلباتي، 4 = السلة، 5 = حسابي (انظر `_mapPendingTabForShell`).
  void requestNavigateToMainTab(int logicalIndex) {
    _pendingMainNavigationIndex = logicalIndex;
    notifyListeners();
  }

  bool isLoading = false;

  String? _sessionError;

  /// أخطاء الجلسة والتوثيق؛ للقراءة يُدمج مع أخطاء الكتالوج/البحث/التصفية/السلة.
  String? get errorMessage =>
      _sessionError ??
      catalog.errorMessage ??
      search.errorMessage ??
      filter.errorMessage ??
      cartState.errorMessage;

  set errorMessage(String? v) {
    _sessionError = v;
    notifyListeners();
  }

  List<Product> get products => catalog.products;
  List<Product> get homeBestSellers => catalog.homeBestSellers;
  List<Product> get homeWallPaints => catalog.homeWallPaints;
  List<Product> get homePlumbing => catalog.homePlumbing;
  List<Product> get homeNewArrivals => catalog.homeNewArrivals;
  List<ProductCategory> get categories => catalog.categories;
  List<ProductCategory> get categoriesForHomePage => catalog.categoriesForHomePage;
  List<Product> get bannerProducts => catalog.bannerProducts;
  List<WpHomeBannerSlide> get wpHomeBanners => catalog.wpHomeBanners;
  List<CartItem> get cart => cartState.cart;
  CustomerProfile? get profile => user.profile;
  set profile(CustomerProfile? v) {
    user.profile = v;
    notifyListeners();
  }

  bool get useFirestoreCatalog => catalog.useFirestoreCatalog;

  String get searchQuery => search.searchQuery;
  List<Product> get searchResults => search.searchResults;
  bool get isSearching => search.isSearching;
  bool get searchHasMore => search.searchHasMore;
  bool get isLoadingMoreSearch => search.isLoadingMoreSearch;

  CatalogActiveFilters? get activeFilters => filter.activeFilters;
  List<Product> get filteredProducts => filter.filteredProducts;
  bool get filterHasMore => filter.filterHasMore;
  bool get isLoadingMoreFilter => filter.isLoadingMoreFilter;
  bool get isApplyingFilters => filter.isApplyingFilters;

  Set<int> favoriteProductIds = <int>{};

  /// العملة الافتراضية للمتجر (الأردن).
  StoreCurrency currency = StoreCurrency.fromWooSettings(
    currencyCode: 'JOD',
    priceNumDecimals: 3,
  );

  double get cartTotal => cartState.cartTotal;

  /// أقسام الرئيسية — مُستخرجة من حقول `category` / `categoryLabel` / `subCategory` على المنتجات (لا تعتمد على مجموعة أقسام فارغة).
  List<ProductDerivedCategory> get derivedCategoriesForHome =>
      deriveCategoriesFromProducts(products);

  ShippingPolicy get shippingPolicy => catalog.shippingPolicy;

  /// مجموع أسعار المنتجات فقط (قبل الشحن).
  double get cartSubtotal => cartTotal;

  double shippingAmountForCart() => shippingPolicy.shippingForCartSubtotal(cartSubtotal);

  double get orderTotalWithShipping => cartSubtotal + shippingAmountForCart();

  int get cartItemCount => cartState.cartItemCount;
  Coupon? get appliedCoupon => cartState.appliedCoupon;
  double get discountAmount => cartState.discountAmount;
  List<Promotion> get appliedPromotions => cartState.appliedPromotions;
  double get promotionsDiscountAmount => cartState.promotionsDiscountAmount;
  bool get freeShippingByPromotion => cartState.freeShippingByPromotion;

  bool get isSearchMode => search.isSearchMode;
  bool get isFilterMode => filter.isFilterMode;

  /// قائمة العرض للشبكة: تصفية، ثم بحث خادمي، ثم الكتالوج العادي.
  List<Product> get displayedProducts {
    if (filter.isFilterMode) return filter.filteredProducts;
    if (search.isSearchMode) return search.searchResults;
    return catalog.products;
  }

  /// كانت تُصفّي محلياً — البحث أصبح خادمياً؛ تُبقى للتوافق كهوية القائمة.
  List<Product> filterProductsBySearch(List<Product> list) => list;

  Future<void> performSearch(String query) => search.performSearch(query);

  void clearSearch() => search.clearSearch();

  Future<void> loadMoreSearchResults() => search.loadMoreSearchResults();

  Future<void> applyFilters(CatalogActiveFilters filters) => filter.applyFilters(filters);

  Future<void> clearFilters() => filter.clearFilters();

  Future<void> loadMoreFilterResults() => filter.loadMoreFilterResults();

  bool isFavorite(int productId) => favoriteProductIds.contains(productId);

  Product? _findProductById(int id) {
    for (final p in catalog.products) {
      if (p.id == id) return p;
    }
    for (final p in search.searchResults) {
      if (p.id == id) return p;
    }
    for (final p in filter.filteredProducts) {
      if (p.id == id) return p;
    }
    for (final p in catalog.homeBestSellers) {
      if (p.id == id) return p;
    }
    for (final p in catalog.homeWallPaints) {
      if (p.id == id) return p;
    }
    for (final p in catalog.homePlumbing) {
      if (p.id == id) return p;
    }
    for (final p in catalog.homeNewArrivals) {
      if (p.id == id) return p;
    }
    for (final p in catalog.bannerProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _detachFavoritesListener() {
    final sub = _favoritesSub;
    _favoritesSub = null;
    sub?.cancel();
  }

  /// مزامنة المفضلة المحلية مع السحابة ثم الاشتراك في التحديثات.
  Future<void> _syncFavoritesAfterAuth() async {
    if (!Firebase.apps.isNotEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _detachFavoritesListener();
      return;
    }
    try {
      await UsersRepository.migrateLocalFavoritesToFirestore(
        userId: uid,
        localIds: favoriteProductIds,
        resolveProduct: _findProductById,
      );
    } on Object {
      debugPrint('[StoreController] migrateLocalFavoritesToFirestore failed');
    }
    _detachFavoritesListener();
    _favoritesSub = UsersRepository.watchFavorites(uid).listen(
      (state) {
        final list = switch (state) {
          FeatureSuccess(:final data) => data,
          _ => <FavoriteProduct>[],
        };
        favoriteProductIds = list.map((e) => int.tryParse(e.productId) ?? 0).where((id) => id > 0).toSet();
        unawaited(_local.saveFavoriteIds(favoriteProductIds));
        notifyListeners();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('[StoreController] watchFavorites: $e\n$st');
      },
    );
  }

  Future<void> toggleFavorite(int productId) async {
    final wasFavorite = favoriteProductIds.contains(productId);
    final next = Set<int>.from(favoriteProductIds);
    if (wasFavorite) {
      next.remove(productId);
    } else {
      next.add(productId);
    }
    favoriteProductIds = next;
    await _local.saveFavoriteIds(favoriteProductIds);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && Firebase.apps.isNotEmpty) {
      try {
        final pid = productId.toString();
        if (wasFavorite) {
          await UsersRepository.removeFromFavorites(uid, pid);
        } else {
          final p = _findProductById(productId);
          final name = p?.name.trim().isNotEmpty == true ? p!.name : 'منتج $productId';
          final img = p != null ? webSafeFirstProductImage(p.images) : '';
          final raw = p?.price ?? '0';
          final price = double.tryParse(raw.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
          await UsersRepository.addToFavorites(
            uid,
            pid,
            productName: name,
            productImage: img,
            productPrice: price,
          );
        }
      } on Object {
        debugPrint('[StoreController] toggleFavorite cloud failed');
      }
    }
    notifyListeners();
  }

  /// إزالة من المفضلة (مثلاً من صفحة المفضلة السحابية) دون الحاجة لوجود المنتج في الذاكرة.
  Future<void> removeFavorite(int productId) async {
    if (!favoriteProductIds.contains(productId)) return;
    favoriteProductIds = Set<int>.from(favoriteProductIds)..remove(productId);
    await _local.saveFavoriteIds(favoriteProductIds);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && Firebase.apps.isNotEmpty) {
      try {
        await UsersRepository.removeFromFavorites(uid, productId.toString());
      } on Object {
        debugPrint('[StoreController] removeFavorite failed');
      }
    }
    notifyListeners();
  }

  List<Product> get favoriteProducts =>
      products.where((p) => favoriteProductIds.contains(p.id)).toList();

  String formatPrice(String rawPrice) => currency.formatAmount(rawPrice);

  String formatMoney(double value) => currency.formatDouble(value);

  Future<SavedCheckoutInfo?> getSavedCheckoutInfo() => _local.getSavedCheckoutInfo();

  Future<void> saveDeliveryInfo(SavedCheckoutInfo info) => _local.saveSavedCheckoutInfo(info);

  @override
  void dispose() {
    _detachFavoritesListener();
    catalog.dispose();
    search.dispose();
    filter.dispose();
    user.dispose();
    super.dispose();
  }

  Future<void> bootstrap() async {
    final swTotal = Stopwatch()..start();
    isLoading = true;
    notifyListeners();
    try {
      final swProfile = Stopwatch()..start();
      user.profile = await _local.getProfile();
      swProfile.stop();
      debugPrint('⏱️ bootstrap profile load: ${swProfile.elapsedMilliseconds}ms');

      final swCart = Stopwatch()..start();
      await cartState.loadPersistedCart();
      swCart.stop();
      debugPrint('⏱️ bootstrap cart load: ${swCart.elapsedMilliseconds}ms');

      favoriteProductIds = await _local.getFavoriteIds();
      await catalog.resolveCatalogSource();
      if (Firebase.apps.isNotEmpty) {
        catalog.attachFirestoreStreams();
        final swInitial = Stopwatch()..start();
        await Future.wait<void>([
          loadCategories(),
          syncLocalProfileWithFirebaseSession(),
          loadInitialProductsPage(),
        ]);
        swInitial.stop();
        debugPrint('⏱️ bootstrap initial parallel data load: ${swInitial.elapsedMilliseconds}ms');
      }
      await loadStoreCurrency();
      if (profile != null && Firebase.apps.isNotEmpty) {
        if (FirebaseAuth.instance.currentUser == null) {
          final bypass = await _local.getLocalBypassSession();
          if (!bypass) {
            await syncChatFirebaseIdentity(profile);
          }
        }
        if (await user.isUserBannedInFirestore()) {
          errorMessage = 'تم حظر حسابك. تواصل مع الدعم.';
          await logout();
        }
      }
      if (Firebase.apps.isNotEmpty) {
        if (FirebaseAuth.instance.currentUser != null) {
          await _syncFavoritesAfterAuth();
        } else {
          _detachFavoritesListener();
        }
      }
    } finally {
      swTotal.stop();
      debugPrint('⏱️ StoreController.bootstrap total: ${swTotal.elapsedMilliseconds}ms');
      isLoading = false;
      notifyListeners();
    }
  }

  /// يطابق الملف المحفوظ مع جلسة Firebase (هاتف أو بريد تركيبي) ويستكمل من Firestore `users/{uid}`.
  Future<void> syncLocalProfileWithFirebaseSession() async {
    await user.syncLocalProfileWithFirebaseSession();
    notifyListeners();
  }

  /// يحدّث [profile] من بيانات `users/{uid}`.
  Future<void> loadProfileFromUserData(Map<String, dynamic>? data) async {
    await user.loadProfileFromUserData(data);
    notifyListeners();
  }

  /// تسجيل دخول برقم الجوال (٩ أرقام) وكلمة المرور — بدون OTP.
  Future<bool> signInWithPhonePassword(String localNineDigits, String password) async {
    if (!Firebase.apps.isNotEmpty) {
      errorMessage = 'يتطلب Firebase.';
      notifyListeners();
      return false;
    }
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
      final un = normalizeJordanPhoneForUsername(localNineDigits);
      final e164 = '+$un';
      await PhonePasswordAuthService.signInWithPhonePassword(phone: e164, password: password);
      await _local.setLocalBypassSession(false);
      await syncLocalProfileWithFirebaseSession();
      if (await user.isUserBannedInFirestore()) {
        errorMessage = 'تم حظر حسابك. تواصل مع الدعم.';
        await logout();
        return false;
      }
      await _syncFavoritesAfterAuth();
      return true;
    } on PhonePasswordAuthException catch (e) {
      errorMessage = e.messageAr;
      return false;
    } on FirebaseAuthException {
      errorMessage = 'تعذر تسجيل الدخول. تحقق من رقم الهاتف وكلمة المرور.';
      return false;
    } on Object {
      errorMessage = 'تعذر تسجيل الدخول حالياً.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// تسجيل دخول بالبريد وكلمة المرور (مناسب للويب).
  Future<bool> signInWithEmailPassword(String email, String password) async {
    errorMessage = 'تم توحيد تسجيل الدخول: استخدم رقم الهاتف وكلمة المرور.';
    notifyListeners();
    return false;
  }

  /// بعد التحقق بالهاتف (OTP): ربط كلمة المرور بحساب Firebase ثم حفظ الاسم وبريد التواصل في Firestore فقط هنا.
  /// [contactEmail] البريد الذي يعرضه العميل (إلزامي للتسجيل). [profile.email] يبقى البريد التركيبي للهاتف.
  Future<bool> linkPasswordAndSaveRegistration({
    required String password,
    required String firstName,
    required String lastName,
    required String contactEmail,
    String addressLine = '',
    String city = '',
    String country = 'JO',
  }) async {
    final ce = contactEmail.trim();
    if (ce.isEmpty) {
      errorMessage = 'البريد الإلكتروني مطلوب.';
      notifyListeners();
      return false;
    }
    final fn = firstName.trim();
    final ln = lastName.trim();
    if (fn.isEmpty || ln.isEmpty) {
      errorMessage = 'الاسم الأول واسم العائلة مطلوبان.';
      notifyListeners();
      return false;
    }
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      errorMessage = 'أكمل التحقق من الهاتف أولاً.';
      return false;
    }
    final uname = PhoneAuthService.jordanUsernameFromFirebaseUser(u);
    if (uname == null) {
      errorMessage = 'رقم الهاتف غير متاح من الجلسة.';
      return false;
    }
    final email = syntheticEmailForPhone(uname);
    final phoneLocal = uname.startsWith('962') && uname.length >= 12 ? uname.substring(3) : '';
    final displayName = '$fn $ln'.trim();
    try {
      final cred = EmailAuthProvider.credential(email: email, password: password);
      await u.linkWithCredential(cred);
    } on FirebaseAuthException {
      // Keep flow deterministic; backend validation handles detailed reason.
    }
    try {
      await u.updateDisplayName(displayName);
    } on Object {
      debugPrint('[StoreController] updateDisplayName skipped');
    }
    final pts = await _local.loyaltyPointsForEmail(email);
    profile = CustomerProfile(
      email: email,
      token: null,
      fullName: displayName,
      firstName: fn,
      lastName: ln,
      phoneLocal: phoneLocal.isNotEmpty ? phoneLocal : null,
      addressLine: addressLine.trim().isNotEmpty ? addressLine.trim() : null,
      city: city.trim().isNotEmpty ? city.trim() : null,
      country: country,
      loyaltyPoints: pts,
      contactEmail: ce,
    );
    await _local.saveProfile(profile!);
    await _local.setLocalBypassSession(false);
    await UsersRepository.syncUserDocument(profile!);
    await syncChatFirebaseIdentity(profile);
    notifyListeners();
    return true;
  }

  /// دخول مؤقت بدون Firebase Auth — للتصفح والكتالوج فقط (لا طلبات تتطلب جلسة Firebase).
  Future<bool> loginWithLocalBypass(String localNineDigits) async {
    if (!isValidJordanMobileLocal(localNineDigits)) {
      errorMessage = 'رقم أردني صحيح يبدأ بـ 7 (9 أرقام).';
      notifyListeners();
      return false;
    }
    try {
      errorMessage = null;
      final un = normalizeJordanPhoneForUsername(localNineDigits);
      final email = syntheticEmailForPhone(un);
      final pts = await _local.loyaltyPointsForEmail(email);
      profile = CustomerProfile(
        email: email,
        token: null,
        fullName: 'زائر',
        loyaltyPoints: pts,
        phoneLocal: localNineDigits,
      );
      await _local.saveProfile(profile!);
      await _local.setLocalBypassSession(true);
      // _api.setJwtToken(null); // LEGACY Woo JWT
      _pendingMainNavigationIndex = 0;
      notifyListeners();
      return true;
    } on Object {
      errorMessage = 'تعذر الدخول المؤقت حالياً.';
      notifyListeners();
      return false;
    }
  }

  /// بعد التحقق بالهاتف في مسار «نسيت كلمة المرور»: تعيين كلمة مرور جديدة ثم مزامنة الملف من Firestore.
  Future<bool> finishForgotPasswordWithNewPassword(String newPassword) async {
    if (!Firebase.apps.isNotEmpty) {
      errorMessage = 'يتطلب Firebase.';
      notifyListeners();
      return false;
    }
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
      await AccountPasswordService.setPasswordAfterPhoneOtpRecovery(newPassword);
      await _local.setLocalBypassSession(false);
      await syncLocalProfileWithFirebaseSession();
      return true;
    } on FirebaseAuthException {
      errorMessage = 'تعذر تحديث كلمة المرور.';
      return false;
    } on Object {
      errorMessage = 'تعذر تحديث كلمة المرور حالياً.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// بعد إتمام Migration Hub من لوحة الأدمن — البث يحدّث الواجهة تلقائياً.
  Future<void> reloadCatalogAfterMigration() => catalog.reloadCatalogAfterMigration();

  Future<void> loadStoreCurrency() async {
    currency = StoreCurrency.fromWooSettings(
      currencyCode: 'JOD',
      priceNumDecimals: 3,
    );
    notifyListeners();
  }

  /// منتجات قسم — من الكتالوج المحمّل (Firestore).
  Future<FeatureState<List<Product>>> fetchProductsByCategory(int categoryId, {int perPage = 100}) =>
      catalog.fetchProductsByCategory(categoryId, perPage: perPage);

  /// منتجات حسب وسم — من الكتالوج المحمّل.
  Future<FeatureState<List<Product>>> fetchProductsByTag(int tagId, {int perPage = 100}) =>
      catalog.fetchProductsByTag(tagId, perPage: perPage);

  Future<FeatureState<List<ProductCategory>>> fetchChildCategories(int parentId) =>
      catalog.fetchChildCategories(parentId);

  /// جلب الصفحة الأولى من الكتالوج (بدون بث كامل) — سحب للتحديث وغيره.
  Future<void> loadInitialProductsPage() => catalog.loadInitialProductsPage();

  /// تمرير لأسفل الرئيسية — تحميل الدفعة التالية من [products].
  Future<void> loadNextProductsPage() => catalog.loadNextProductsPage();

  /// جلب لمرة واحدة — يعيد التحميل من الصفحة الأولى (ترقيم).
  Future<void> loadProducts() => catalog.loadProducts();

  Future<void> loadCategories() => catalog.loadCategories();

  /// بانرات الصفحة الرئيسية من Firestore `home_banners` (يدوي؛ البث يحدّث [wpHomeBanners]).
  Future<void> loadWpHomeBanners() => catalog.loadWpHomeBanners();

  /// صور بانر احتياطية من المنتجات المحمّلة.
  Future<void> loadBannerProducts() => catalog.loadBannerProducts();

  Future<void> loadHomeSections() => catalog.loadHomeSections();

  /// إرسال رمز OTP إلى رقم أردني (9 أرقام تبدأ بـ 7).
  /// [forgotPassword]: مثل التسجيل — لا يُستدعى [_finalizePhoneSession] عند التحقق التلقائي حتى يكتمل المسار لاحقاً.
  /// [isResendSms]: `true` لإعادة الإرسال باستخدام [phoneResendToken] من آخر `codeSent`.
  Future<bool> sendPhoneVerificationCode(
    String localNineDigits, {
    bool isRegistration = false,
    bool forgotPassword = false,
    String? firstName,
    String? lastName,
    bool isResendSms = false,
  }) async {
    if (!Firebase.apps.isNotEmpty) {
      errorMessage = 'يتطلب Firebase.';
      notifyListeners();
      return false;
    }
    try {
      isLoading = true;
      errorMessage = null;
      final tokenForResend = isResendSms ? phoneResendToken : null;
      phoneVerificationId = null;
      phoneResendToken = null;
      notifyListeners();
      final e164 = PhoneAuthService.jordanPhoneE164(localNineDigits);
      final result = await PhoneAuthService.startVerification(
        e164,
        forceResendingToken: tokenForResend,
      );
      if (result.verificationId == PhoneAuthService.autoVerifiedSentinel) {
        // التسجيل / نسيان كلمة المرور: لا نكتب الملف المحلي/Firestore حتى يُكمل المسار صراحة.
        if (isRegistration || forgotPassword) {
          phoneVerificationId = PhoneAuthService.autoVerifiedSentinel;
          phoneResendToken = result.resendToken;
          return true;
        }
        return await _finalizePhoneSession(
          isRegistration: isRegistration,
          firstName: firstName,
          lastName: lastName,
        );
      }
      phoneVerificationId = result.verificationId;
      phoneResendToken = result.resendToken;
      return true;
    } on FirebaseAuthException {
      errorMessage = 'تعذر إرسال رمز التحقق.';
      return false;
    } on Object {
      errorMessage = 'تعذر إرسال رمز التحقق حالياً.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// إكمال التسجيل أو الدخول بعد إدخال رمز SMS.
  /// [skipProfileFinalize]: `true` للتسجيل أو استعادة كلمة المرور — لا يُحدَّث [profile] ولا Firestore حتى [linkPasswordAndSaveRegistration] أو استعادة كلمة المرور.
  Future<bool> verifyPhoneCode(
    String smsCode, {
    required bool isRegistration,
    bool skipProfileFinalize = false,
    String? firstName,
    String? lastName,
  }) async {
    if (!Firebase.apps.isNotEmpty) {
      errorMessage = 'يتطلب Firebase.';
      return false;
    }
    final vid = phoneVerificationId;
    if (vid == null || vid.isEmpty) {
      errorMessage = 'أرسل رمز التحقق أولاً.';
      return false;
    }
    if (vid == PhoneAuthService.autoVerifiedSentinel) {
      if (skipProfileFinalize) {
        phoneVerificationId = null;
        phoneResendToken = null;
        notifyListeners();
        return true;
      }
      final ok = await _finalizePhoneSession(
        isRegistration: isRegistration,
        firstName: firstName,
        lastName: lastName,
      );
      if (ok) {
        phoneVerificationId = null;
        phoneResendToken = null;
      }
      return ok;
    }
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
      await PhoneAuthService.signInWithSmsCode(verificationId: vid, smsCode: smsCode);
      phoneVerificationId = null;
      phoneResendToken = null;
      if (skipProfileFinalize) {
        return true;
      }
      return await _finalizePhoneSession(
        isRegistration: isRegistration,
        firstName: firstName,
        lastName: lastName,
      );
    } on FirebaseAuthException {
      errorMessage = 'رمز التحقق غير صالح.';
      return false;
    } on Object {
      errorMessage = 'تعذر التحقق من الرمز حالياً.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _finalizePhoneSession({
    required bool isRegistration,
    String? firstName,
    String? lastName,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      errorMessage = 'تعذر إنشاء الجلسة.';
      return false;
    }
    final uname = PhoneAuthService.jordanUsernameFromFirebaseUser(u);
    if (uname == null) {
      errorMessage = 'رقم الهاتف غير متاح من الحساب.';
      return false;
    }
    final email = syntheticEmailForPhone(uname);
    String? fullName;
    if (isRegistration) {
      fullName = '${firstName ?? ''} ${lastName ?? ''}'.trim();
      if (fullName.isEmpty) fullName = null;
    } else {
      fullName = profile?.fullName ?? (await _local.getProfile())?.fullName;
    }
    final pts = await _local.loyaltyPointsForEmail(email);
    final pl = uname.startsWith('962') && uname.length >= 12 ? uname.substring(3) : null;
    profile = CustomerProfile(
      email: email,
      token: null,
      fullName: fullName,
      firstName: firstName?.trim().isNotEmpty == true ? firstName!.trim() : null,
      lastName: lastName?.trim().isNotEmpty == true ? lastName!.trim() : null,
      phoneLocal: pl,
      loyaltyPoints: pts,
    );
    await _local.saveProfile(profile!);
    // _api.setJwtToken(null); // LEGACY Woo JWT
    await _local.setLocalBypassSession(false);
    await syncChatFirebaseIdentity(profile);
    if (await user.isUserBannedInFirestore()) {
      errorMessage = 'تم حظر حسابك. تواصل مع الدعم.';
      await logout();
      return false;
    }
    return true;
  }

  void clearPhoneVerificationState() {
    phoneVerificationId = null;
    phoneResendToken = null;
    PhoneAuthService.resetWebPendingVerification();
    notifyListeners();
  }

  Future<void> logout() async {
    _detachFavoritesListener();
    await user.clearSessionProfile();
    phoneVerificationId = null;
    phoneResendToken = null;
    favoriteProductIds = await _local.getFavoriteIds();
    notifyListeners();
  }

  Future<void> addToCart(
    Product product, {
    String storeId = 'ammarjo',
    String storeName = 'متجر عمار جو',
  }) =>
      cartState.addToCart(product, storeId: storeId, storeName: storeName);

  Future<void> addCartItem(CartItem item) => cartState.addCartItem(item);

  Future<void> updateQuantity(int productId, int quantity, {String storeId = 'ammarjo'}) =>
      cartState.updateQuantity(productId, quantity, storeId: storeId);

  Future<void> increaseCartLineQty(CartItem item) => cartState.increaseCartLineQty(item);

  Future<void> decreaseCartLineQty(CartItem item) => cartState.decreaseCartLineQty(item);

  Future<void> removeFromCart(int productId, {String storeId = 'ammarjo'}) =>
      cartState.removeFromCart(productId, storeId: storeId);

  Future<void> removeCartLine(CartItem item) => cartState.removeCartLine(item);
  Future<bool> applyCoupon(String code, String userId, {List<CartItem>? lines}) =>
      cartState.applyCoupon(code, userId, lines: lines);
  void removeCoupon() => cartState.removeCoupon();
  Future<bool> applyPromotions(String userId, {List<CartItem>? lines}) =>
      cartState.applyPromotions(userId, lines: lines);
  void clearPromotions() => cartState.clearPromotions();

  /// شحن + خصومات على [lines] فقط (لملخص الدفع عند `checkoutLines`).
  Future<
      ({
        StoreShippingComputation shipping,
        double couponDiscount,
        double promotionsDiscount,
        bool freeShipping,
      })> previewCheckoutTotals({
    required List<CartItem> lines,
    required String userId,
    String? userCity,
  }) async {
    final shipping = await computeShippingForCartLines(lines, userCity: userCity);
    final d = await cartState.checkoutDiscountBreakdownForLines(lines, userId);
    return (
      shipping: shipping,
      couponDiscount: d.couponDiscount,
      promotionsDiscount: d.promotionsDiscount,
      freeShipping: d.freeShipping,
    );
  }

  /// تحديث بيانات المنتجات في السلة من Firestore (`products`).
  Future<void> refreshCartFromCatalog() => cartState.refreshCartFromCatalog();

  /// [cartLines] إن وُجدت يُكمَّل الطلب لهذه الأسطر فقط ويُزال من السلة ما يطابقها (طلب متعدد المتاجر).
  Future<StoreShippingComputation> computeShippingForCartLines(
    List<CartItem> lines, {
    String? userCity,
  }) async {
    final grouped = <String, List<CartItem>>{};
    for (final line in lines) {
      grouped.putIfAbsent(line.storeId, () => <CartItem>[]).add(line);
    }
    final list = <StoreShippingLineCost>[];
    final uncoveredStoreNames = <String>[];
    final noDeliveryStoreNames = <String>[];
    for (final entry in grouped.entries) {
      final storeId = entry.key.trim();
      final items = entry.value;
      final subtotal = items.fold<double>(0, (s, e) => s + e.totalPrice);
      final itemCount = items.fold<int>(0, (s, e) => s + e.quantity);
      final display = items.first.storeName.trim().isEmpty ? 'متجر' : items.first.storeName;
      if (storeId.isEmpty || storeId == 'ammarjo') {
        final fee = store_shipping.ShippingPolicy.defaults.calculateShipping(
          subtotal: subtotal,
          itemCount: itemCount,
        );
        list.add(StoreShippingLineCost(storeId: storeId, storeName: display, subtotal: subtotal, shippingCost: fee));
        continue;
      }
      final storeState = await RestStoreRepository.instance.fetchStoreDocument(storeId);
      final data = switch (storeState) {
        FeatureSuccess(:final data) => data.toMap(),
        _ => <String, dynamic>{},
      };
      final hasOwn = data['hasOwnDrivers'] != false && data['has_own_drivers'] != false;
      if (!hasOwn) {
        noDeliveryStoreNames.add(display);
        list.add(StoreShippingLineCost(storeId: storeId, storeName: display, subtotal: subtotal, shippingCost: 0));
        continue;
      }
      final policy = store_shipping.ShippingPolicy.fromMap(
        data['shippingPolicy'] is Map ? Map<String, dynamic>.from(data['shippingPolicy'] as Map) : null,
      );
      final fee = policy.calculateShipping(subtotal: subtotal, itemCount: itemCount);
      final city = userCity?.trim() ?? '';
      if (city.isNotEmpty && !_storeDeliversToCustomerArea(data, city)) {
        uncoveredStoreNames.add(display);
      }
      list.add(StoreShippingLineCost(storeId: storeId, storeName: display, subtotal: subtotal, shippingCost: fee));
    }
    final shippingTotal = list.fold<double>(0, (s, e) => s + e.shippingCost);
    return StoreShippingComputation(
      lines: list,
      totalShipping: shippingTotal,
      uncoveredStoreNames: uncoveredStoreNames,
      noDeliveryStoreNames: noDeliveryStoreNames,
    );
  }

  /// محافظات التوصيل من المتجر + تطابق مع مدينة العميل.
  bool _storeDeliversToCustomerArea(Map<String, dynamic> data, String cityRaw) {
    final c = matchJordanRegion(cityRaw.trim()) ?? cityRaw.trim();
    if (c.isEmpty) return true;
    final rawAreas = data['deliveryAreas'] ?? data['delivery_areas'];
    final areas = <String>[];
    if (rawAreas is List) {
      for (final e in rawAreas) {
        final t = e?.toString().trim() ?? '';
        if (t.isNotEmpty) areas.add(t);
      }
    }
    if (areas.isEmpty) {
      return _storeCoversCity(data, c);
    }
    if (areas.contains('كل الأردن')) return true;
    for (final a in areas) {
      final ma = matchJordanRegion(a) ?? a;
      if (ma == c || a == c) return true;
    }
    return false;
  }

  bool _storeCoversCity(Map<String, dynamic> data, String city) {
    final c = city.trim();
    if (c.isEmpty) return true;
    final scope = data['sellScope']?.toString().trim();
    if (scope == 'all_jordan') return true;
    final storeCity = data['city']?.toString().trim();
    if (scope == 'city' && storeCity != null && storeCity.isNotEmpty) {
      return storeCity == c;
    }
    final raw = data['cities'];
    if (raw is List) {
      final list = raw.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
      return list.contains(c) || list.contains('all') || list.contains('all_jordan');
    }
    return true;
  }

  Future<bool> placeOrder({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String address1,
    required String city,
    required String country,
    double? latitude,
    double? longitude,
    List<CartItem>? cartLines,
  }) async {
    final lines = cartLines ?? cartState.cart;
    if (lines.isEmpty) {
      errorMessage = 'السلة فارغة.';
      notifyListeners();
      return false;
    }
    if (FirebaseAuth.instance.currentUser == null) {
      errorMessage = 'يجب تسجيل الدخول لإتمام الطلب.';
      notifyListeners();
      return false;
    }
    if (!Firebase.apps.isNotEmpty) {
      errorMessage = 'يتطلب Firebase لإتمام الطلب.';
      notifyListeners();
      return false;
    }
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
      final subtotal = lines.fold<double>(0, (s, e) => s + e.totalPrice);
      final shipping = await computeShippingForCartLines(lines, userCity: city);
      if (shipping.noDeliveryStoreNames.isNotEmpty) {
        errorMessage = 'لا يوجد توصيل من: ${shipping.noDeliveryStoreNames.join('، ')}';
        return false;
      }
      if (shipping.uncoveredStoreNames.isNotEmpty) {
        errorMessage = 'لا يوجد توصيل لمنطقتك من: ${shipping.uncoveredStoreNames.join('، ')}';
        return false;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        errorMessage = 'انتهت الجلسة. سجّل الدخول مرة أخرى.';
        return false;
      }
      final CheckoutScopedDiscounts scoped = cartLines != null
          ? await _checkoutScopedDiscounts(lines: lines, userId: uid)
          : CheckoutScopedDiscounts(
              couponDiscount: cartState.discountAmount,
              promotionsDiscount: cartState.promotionsDiscountAmount,
              freeShipping: cartState.freeShippingByPromotion,
              promotionIds: cartState.appliedPromotions.map((e) => e.id).toList(),
            );
      final ship = scoped.freeShipping ? 0.0 : shipping.totalShipping;
      final couponCode = scoped.couponDiscount > 0 ? cartState.appliedCoupon?.code : null;
      final discount = scoped.couponDiscount + scoped.promotionsDiscount;
      final beforeDiscountTotal = subtotal + ship;
      final grandTotal = (beforeDiscountTotal - discount) < 0 ? 0.0 : (beforeDiscountTotal - discount);
      var orderEmail = email.trim();
      if (orderEmail.isEmpty) {
        orderEmail = profile?.email.trim() ?? '';
      }
      if (orderEmail.isEmpty) {
        final u = FirebaseAuth.instance.currentUser;
        final un = PhoneAuthService.jordanUsernameFromFirebaseUser(u);
        if (un != null) {
          orderEmail = syntheticEmailForPhone(un);
        }
      }
      if (orderEmail.isEmpty) {
        errorMessage = 'تعذر تحديد بريد الطلب. سجّل الخروج ثم أعد تسجيل الدخول.';
        isLoading = false;
        notifyListeners();
        return false;
      }
      final orderState = await BackendOrderRepository.instance.createOrderFromCart(
        cart: lines,
        cartSubtotal: subtotal,
        shippingFee: ship,
        shippingByStore: {
          for (final s in shipping.lines) s.storeId: s.shippingCost,
        },
        orderTotal: grandTotal,
        couponCode: couponCode,
        discountAmount: discount > 0 ? discount : 0.0,
        promotionIds: scoped.promotionIds,
        customerUid: uid,
        customerEmail: orderEmail,
        firstName: firstName,
        lastName: lastName,
        email: orderEmail,
        phone: phone,
        address1: address1,
        city: city,
        country: country,
        latitude: latitude,
        longitude: longitude,
      );
      final orderId = switch (orderState) {
        FeatureSuccess(:final data) => data,
        FeatureFailure() => '',
        _ => '',
      };
      if (orderState case FeatureFailure(:final message)) {
        errorMessage = message;
      }
      if (orderId.trim().isEmpty) {
        errorMessage = 'تعذّر إتمام الطلب. تحقق من الاتصال وحاول لاحقاً.';
        return false;
      }
      if (cartLines != null) {
        for (final line in cartLines) {
          await cartState.removeFromCart(line.product.id, storeId: line.storeId);
        }
      } else {
        await cartState.clearCart();
      }
      cartState.removeCoupon();
      cartState.clearPromotions();
      await _local.saveSavedCheckoutInfo(
        SavedCheckoutInfo(
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          email: email.trim().isNotEmpty ? email.trim() : (profile?.email.trim() ?? ''),
          phone: phone.trim(),
          address1: address1.trim(),
          city: city.trim(),
          country: country.trim().isNotEmpty ? country.trim() : 'JO',
        ),
      );
      if (profile != null) {
        var next = profile!;
        final digits = phone.replaceAll(RegExp(r'\D'), '');
        next = next.copyWith(
          firstName: firstName.trim().isNotEmpty ? firstName.trim() : next.firstName,
          lastName: lastName.trim().isNotEmpty ? lastName.trim() : next.lastName,
          phoneLocal: digits.length >= 9 ? digits.substring(digits.length - 9) : next.phoneLocal,
          addressLine: address1.trim().isNotEmpty ? address1.trim() : next.addressLine,
          city: city.trim().isNotEmpty ? city.trim() : next.city,
          country: country.trim().isNotEmpty ? country.trim() : (next.country ?? 'JO'),
        );
        profile = next;
        await _local.saveProfile(profile!);
        await UsersRepository.syncUserDocument(profile!);
      }
      return true;
    } on Object {
      errorMessage = 'تعذّر إتمام الطلب حالياً.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<CheckoutScopedDiscounts> _checkoutScopedDiscounts({
    required List<CartItem> lines,
    required String userId,
  }) async {
    final d = await cartState.checkoutDiscountBreakdownForLines(lines, userId);
    return CheckoutScopedDiscounts(
      couponDiscount: d.couponDiscount,
      promotionsDiscount: d.promotionsDiscount,
      freeShipping: d.freeShipping,
      promotionIds: d.promotionIds,
    );
  }

  /// Deprecated: points are now awarded only on `delivered`.
}

/// خصومات مُعاد حسابها لأسطر طلب جزئية (متجر واحد من السلة).
class CheckoutScopedDiscounts {
  const CheckoutScopedDiscounts({
    required this.couponDiscount,
    required this.promotionsDiscount,
    required this.freeShipping,
    required this.promotionIds,
  });

  final double couponDiscount;
  final double promotionsDiscount;
  final bool freeShipping;
  final List<String> promotionIds;
}

class StoreShippingLineCost {
  const StoreShippingLineCost({
    required this.storeId,
    required this.storeName,
    required this.subtotal,
    required this.shippingCost,
  });

  final String storeId;
  final String storeName;
  final double subtotal;
  final double shippingCost;
}

class StoreShippingComputation {
  const StoreShippingComputation({
    required this.lines,
    required this.totalShipping,
    required this.uncoveredStoreNames,
    this.noDeliveryStoreNames = const <String>[],
  });

  final List<StoreShippingLineCost> lines;
  final double totalShipping;
  final List<String> uncoveredStoreNames;
  /// متاجر أوقفت التوصيل ([hasOwnDrivers] = false).
  final List<String> noDeliveryStoreNames;
}
