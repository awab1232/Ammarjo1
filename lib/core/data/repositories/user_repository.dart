import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../features/store/domain/favorite_product.dart';
import '../../../features/store/domain/models.dart';
import '../../contracts/feature_state.dart';
import '../../services/backend_user_client.dart';
import '../../services/user_service.dart';

/// Customer profile, favorites — **backend HTTP only** (`BackendUserClient`).
abstract class UserRepository {
  CustomerProfile? customerProfileFromUserDocData(Map<String, dynamic>? d);

  Future<CustomerProfile?> fetchProfileDocument(String uid);

  Future<void> syncUserDocument(CustomerProfile profile);

  Future<void> incrementPoints(String uid, int amount);

  Future<void> addPointsForOrder({
    required String userId,
    required int points,
    required String orderId,
  });

  Future<void> addToFavorites(
    String userId,
    String productId, {
    required String productName,
    required String productImage,
    required double productPrice,
  });

  Future<void> removeFromFavorites(String userId, String productId);

  Future<bool> isFavorite(String userId, String productId);

  Stream<FeatureState<List<FavoriteProduct>>> watchFavorites(String userId);

  Future<void> migrateLocalFavoritesToFirestore({
    required String userId,
    required Set<int> localIds,
    required Product? Function(int productId) resolveProduct,
  });

  Future<({
    List<Map<String, dynamic>> items,
    String? nextCursor,
    bool hasMore,
  })> getUsersPage({
    required int limit,
    String? cursor,
  });

  /// أول تسجيل بعد [createUserWithEmailAndPassword] — وثيقة `users/{uid}`.
  Future<void> setInitialRegistrationDocument(String uid, Map<String, dynamic> data);

  Future<bool> isUserBanned(String uid);

  /// One-shot read of `users/{uid}` (login / delivery / profile checks).
  Future<Map<String, dynamic>?> fetchUserDocument(String uid);

  /// Partial update of `users/{uid}`.
  Future<void> updateUserFields(String uid, Map<String, dynamic> fields);

  /// Drawer / profile — user document data without exposing Firestore types to UI.
  Future<Map<String, dynamic>?> fetchUserMap(String uid);

  /// Technician signup — active specialties (one-shot; refresh UI manually if needed).
  Future<FeatureState<List<Map<String, dynamic>>>> fetchActiveTechSpecialtiesList();
}

class BackendUserRepository implements UserRepository {
  BackendUserRepository._();
  static final BackendUserRepository instance = BackendUserRepository._();

  @override
  CustomerProfile? customerProfileFromUserDocData(Map<String, dynamic>? d) =>
      UserService.instance.customerProfileFromMap(d);

  @override
  Future<CustomerProfile?> fetchProfileDocument(String uid) async {
    final data = await BackendUserClient.instance.fetchUserById(uid);
    return UserService.instance.customerProfileFromMap(data);
  }

  @override
  Future<void> syncUserDocument(CustomerProfile profile) async {
    if (!Firebase.apps.isNotEmpty) return;
    // `/users/{id}` expects the Firebase UID (same as registration `setInitialRegistrationDocument`), not the synthetic phone email.
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;
    await BackendUserClient.instance.patchUser(uid, <String, dynamic>{
      'name': profile.displayName,
      'firstName': profile.firstName,
      'lastName': profile.lastName,
      'email': profile.email.trim(),
      'phone': profile.phoneLocal,
      'addressLine': profile.addressLine,
      'city': profile.city,
      'country': profile.country ?? 'JO',
      'loyaltyPoints': profile.loyaltyPoints,
      'contactEmail': profile.contactEmail,
    });
  }

  @override
  Future<void> incrementPoints(String uid, int amount) async {
    if (amount <= 0) return;
    await BackendUserClient.instance.patchUser(uid, <String, dynamic>{'loyaltyPointsDelta': amount});
  }

  @override
  Future<void> addPointsForOrder({
    required String userId,
    required int points,
    required String orderId,
  }) =>
      BackendUserClient.instance.patchUser(userId, <String, dynamic>{'addPointsForOrder': {'points': points, 'orderId': orderId}});

  @override
  Future<void> addToFavorites(
    String userId,
    String productId, {
    required String productName,
    required String productImage,
    required double productPrice,
  }) =>
      BackendUserClient.instance.putUserFavorite(userId, <String, dynamic>{
        'productId': productId,
        'productName': productName,
        'productImage': productImage,
        'productPrice': productPrice,
      });

  @override
  Future<void> removeFromFavorites(String userId, String productId) =>
      BackendUserClient.instance.deleteUserFavorite(userId, productId);

  @override
  Future<bool> isFavorite(String userId, String productId) async {
    final state = await BackendUserClient.instance.fetchUserFavorites(userId);
    if (state is! FeatureSuccess<List<Map<String, dynamic>>>) return false;
    return state.data.any((e) => e['productId']?.toString() == productId);
  }

  @override
  Stream<FeatureState<List<FavoriteProduct>>> watchFavorites(String userId) async* {
    while (true) {
      try {
        final rowsState = await BackendUserClient.instance.fetchUserFavorites(userId);
        if (rowsState is! FeatureSuccess<List<Map<String, dynamic>>>) {
          yield switch (rowsState) {
            FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
            _ => FeatureState.failure('Failed to load favorites.'),
          };
          await Future<void>.delayed(const Duration(seconds: 4));
          continue;
        }
        final rows = rowsState.data;
        yield FeatureState.success(
          rows
              .map((e) => FavoriteProduct.fromMap(
                    e['productId']?.toString() ?? '',
                    Map<String, dynamic>.from(e),
                  ))
              .toList(),
        );
      } on Object {
        yield FeatureState.failure('Failed to load favorites.');
      }
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  @override
  Future<void> migrateLocalFavoritesToFirestore({
    required String userId,
    required Set<int> localIds,
    required Product? Function(int productId) resolveProduct,
  }) =>
      Future.wait(localIds.map((id) async {
        if (id <= 0) return;
        final p = resolveProduct(id);
        final rawPrice = p?.price;
        final parsedPrice = rawPrice == null
            ? null
            : double.tryParse(rawPrice.replaceAll(RegExp(r'[^\d.]'), ''));
        if (parsedPrice == null) return;
        await BackendUserClient.instance.putUserFavorite(userId, <String, dynamic>{
          'productId': '$id',
          'productName': p?.name ?? 'منتج $id',
          'productImage': p == null || p.images.isEmpty ? '' : p.images.first,
          'productPrice': parsedPrice,
        });
      }));

  @override
  Future<({
    List<Map<String, dynamic>> items,
    String? nextCursor,
    bool hasMore,
  })> getUsersPage({
    required int limit,
    String? cursor,
  }) async =>
      (items: const <Map<String, dynamic>>[], nextCursor: null, hasMore: false);

  @override
  Future<void> setInitialRegistrationDocument(String uid, Map<String, dynamic> data) async {
    await BackendUserClient.instance.patchUser(uid, data);
  }

  @override
  Future<bool> isUserBanned(String uid) async {
    final doc = await BackendUserClient.instance.fetchUserById(uid);
    return UserService.instance.isUserBannedFromData(doc);
  }

  @override
  Future<Map<String, dynamic>?> fetchUserDocument(String uid) => BackendUserClient.instance.fetchUserById(uid);

  @override
  Future<void> updateUserFields(String uid, Map<String, dynamic> fields) async {
    if (fields.isEmpty) return;
    await BackendUserClient.instance.patchUser(uid, fields);
  }

  @override
  Future<Map<String, dynamic>?> fetchUserMap(String uid) async {
    return BackendUserClient.instance.fetchUserById(uid);
  }

  @override
  Future<FeatureState<List<Map<String, dynamic>>>> fetchActiveTechSpecialtiesList() async {
    try {
      final state = await BackendUserClient.instance.fetchTechSpecialties();
      return switch (state) {
        FeatureSuccess(:final data) => FeatureState.success(data),
        FeatureFailure(:final message, :final cause) => FeatureState.failure(message, cause),
        _ => FeatureState.failure('Failed to load tech specialties.'),
      };
    } on Object {
      return FeatureState.failure('Failed to load tech specialties.');
    }
  }
}
